defmodule Ichor.AgentWatchdog.NudgePolicy do
  @moduledoc """
  Pure escalation policy helpers for stale agent nudging.

  No side effects. All functions are predicates, accessors, or fold operations.
  """

  @doc "True if the agent is active, has a session_id, and has exceeded the stale threshold."
  @spec stale?(map(), DateTime.t(), non_neg_integer()) :: boolean()
  def stale?(agent, now, threshold) do
    agent_session_id(agent) != nil and
      agent[:status] == :active and
      agent[:last_event_at] != nil and
      DateTime.diff(now, agent[:last_event_at], :second) > threshold
  end

  @doc "Return the session_id from an agent metadata map."
  @spec agent_session_id(map()) :: String.t() | nil
  def agent_session_id(agent), do: agent[:session_id] || agent[:agent_id]

  @doc "Non-tmux agents cap at level 0 (warn only). Tmux agents use the configured max."
  @spec effective_max_level(map(), non_neg_integer()) :: non_neg_integer()
  def effective_max_level(%{channels: %{tmux: tmux}}, max) when not is_nil(tmux), do: max
  def effective_max_level(_agent, _max), do: 0

  @doc "Build a default escalation entry with last_nudge_at set to trigger immediately."
  @spec default_entry(DateTime.t(), non_neg_integer()) :: map()
  def default_entry(now, nudge_interval) do
    %{
      level: -1,
      last_nudge_at: DateTime.add(now, -nudge_interval - 1, :second),
      stale_since: now
    }
  end

  @doc """
  Fold over stale agents, advancing escalation entries where the nudge interval has elapsed.

  Returns the updated escalations map. Side-effect dispatch (execute_fn) is called per
  escalation step and must be supplied by the caller.
  """
  @spec process_escalations(
          [map()],
          map(),
          DateTime.t(),
          non_neg_integer(),
          non_neg_integer(),
          (String.t(), map(), non_neg_integer() -> :ok)
        ) :: map()
  def process_escalations(stale_agents, escalations, now, nudge_interval, max_level, execute_fn) do
    Enum.reduce(stale_agents, escalations, fn agent, acc ->
      session_id = agent_session_id(agent)
      entry = Map.get(acc, session_id, default_entry(now, nudge_interval))
      maybe_escalate(acc, session_id, agent, entry, now, nudge_interval, max_level, execute_fn)
    end)
  end

  defp maybe_escalate(
         acc,
         session_id,
         agent,
         entry,
         now,
         nudge_interval,
         max_level,
         execute_fn
       ) do
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
