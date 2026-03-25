defmodule Ichor.Projector.AgentWatchdog.EscalationEngine do
  @moduledoc """
  Pure escalation decision engine. Takes agent staleness data and returns escalation
  actions without executing them.

  Determines which stale agents need to advance to the next escalation level and
  calls the provided execute_fn for each transition. The actual side effects
  (signals, HITL, Bus.send) remain in the caller.
  """

  @doc """
  Process all stale agents and advance escalation levels as warranted.

  Returns the updated escalations map. The `execute_fn` is called for each
  agent that transitions to a new level: `execute_fn.(session_id, agent, new_level)`.
  """
  @spec process_escalations(
          stale_agents :: [map()],
          escalations :: map(),
          now :: DateTime.t(),
          nudge_interval :: non_neg_integer(),
          max_level :: non_neg_integer(),
          execute_fn :: (String.t(), map(), non_neg_integer() -> any())
        ) :: map()
  def process_escalations(stale_agents, escalations, now, nudge_interval, max_level, execute_fn) do
    Enum.reduce(stale_agents, escalations, fn agent, acc ->
      session_id = agent_session_id(agent)
      entry = Map.get(acc, session_id, default_entry(now, nudge_interval))
      maybe_escalate(acc, session_id, agent, entry, now, nudge_interval, max_level, execute_fn)
    end)
  end

  @doc """
  Builds the default escalation entry for a newly stale agent.

  Sets `last_nudge_at` far enough in the past that the agent is immediately
  eligible for its first nudge on the next beat.
  """
  @spec default_entry(now :: DateTime.t(), nudge_interval :: non_neg_integer()) :: map()
  def default_entry(now, nudge_interval) do
    %{
      level: -1,
      last_nudge_at: DateTime.add(now, -nudge_interval - 1, :second),
      stale_since: now
    }
  end

  @doc """
  Returns the effective maximum escalation level for an agent.

  Agents without a tmux channel cap out at level 0 (warning only); agents with
  a tmux channel can escalate up to `max`.
  """
  @spec effective_max_level(agent :: map(), max :: non_neg_integer()) :: non_neg_integer()
  def effective_max_level(%{channels: %{tmux: tmux}}, max) when not is_nil(tmux), do: max
  def effective_max_level(_agent, _max), do: 0

  @doc """
  Returns true when an active agent has exceeded the staleness threshold.
  """
  @spec stale?(agent :: map(), now :: DateTime.t(), threshold :: non_neg_integer()) :: boolean()
  def stale?(agent, now, threshold) do
    agent_session_id(agent) != nil and
      agent[:status] == :active and
      agent[:last_event_at] != nil and
      DateTime.diff(now, agent[:last_event_at], :second) > threshold
  end

  @doc """
  Returns the session_id for an agent metadata map.
  """
  @spec agent_session_id(agent :: map()) :: String.t() | nil
  def agent_session_id(agent), do: agent[:session_id] || agent[:id]

  # Private

  defp maybe_escalate(acc, session_id, agent, entry, now, nudge_interval, max_level, execute_fn) do
    since_last = DateTime.diff(now, entry.last_nudge_at, :second)
    effective_max = effective_max_level(agent, max_level)

    if since_last >= nudge_interval and entry.level < effective_max do
      new_level = entry.level + 1
      execute_fn.(session_id, agent, new_level)

      Map.put(acc, session_id, %{
        level: new_level,
        last_nudge_at: now,
        stale_since: entry.stale_since
      })
    else
      acc
    end
  end
end
