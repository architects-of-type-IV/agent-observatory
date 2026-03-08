defmodule Observatory.NudgeEscalator do
  @moduledoc """
  Progressive agent nudging with 4-level escalation.

  Subscribes to heartbeat ticks and checks agent staleness:
    Level 0 (warn):      Log warning, broadcast alert
    Level 1 (nudge):     Send tmux message asking if agent is alive
    Level 2 (escalate):  HITL pause + operator alert
    Level 3 (terminate): Mark as zombie, broadcast for cleanup

  Thresholds are configurable via application env:
    config :observatory, NudgeEscalator,
      stale_threshold_sec: 120,
      nudge_interval_sec: 60,
      max_level: 3
  """
  use GenServer
  require Logger

  alias Observatory.Gateway.AgentRegistry
  alias Observatory.Gateway.Channels.Tmux
  alias Observatory.Gateway.HITLRelay

  @default_stale_threshold 120
  @default_nudge_interval 60
  @default_max_level 3

  defstruct escalations: %{}

  # escalations: %{session_id => %{level: 0..3, last_nudge_at: DateTime, stale_since: DateTime}}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Get current escalation state for all tracked sessions."
  def get_state, do: GenServer.call(__MODULE__, :get_state)

  @doc "Reset escalation for a session (e.g., when activity resumes)."
  def reset(session_id), do: GenServer.cast(__MODULE__, {:reset, session_id})

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Observatory.PubSub, "heartbeat")
    Phoenix.PubSub.subscribe(Observatory.PubSub, "events:stream")
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_info({:heartbeat, _count}, state) do
    state = check_and_escalate(state)
    {:noreply, state}
  end

  # Activity on a session resets its escalation
  def handle_info({:new_event, event}, state) do
    session_id = event.session_id

    if Map.has_key?(state.escalations, session_id) do
      {:noreply, %{state | escalations: Map.delete(state.escalations, session_id)}}
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.escalations, state}
  end

  @impl true
  def handle_cast({:reset, session_id}, state) do
    {:noreply, %{state | escalations: Map.delete(state.escalations, session_id)}}
  end

  defp check_and_escalate(state) do
    now = DateTime.utc_now()
    stale_threshold = config(:stale_threshold_sec, @default_stale_threshold)
    nudge_interval = config(:nudge_interval_sec, @default_nudge_interval)
    max_level = config(:max_level, @default_max_level)

    agents = AgentRegistry.list_all()

    stale_agents =
      agents
      |> Enum.filter(fn agent ->
        agent[:status] == :active &&
          agent[:last_event_at] &&
          DateTime.diff(now, agent[:last_event_at], :second) > stale_threshold
      end)

    escalations =
      Enum.reduce(stale_agents, state.escalations, fn agent, acc ->
        session_id = agent[:session_id] || agent[:agent_id]

        entry =
          Map.get(acc, session_id, %{
            level: -1,
            last_nudge_at: DateTime.add(now, -nudge_interval - 1, :second),
            stale_since: now
          })

        since_last = DateTime.diff(now, entry.last_nudge_at, :second)

        if since_last >= nudge_interval && entry.level < max_level do
          new_level = entry.level + 1
          execute_escalation(session_id, agent, new_level)

          Map.put(acc, session_id, %{
            level: new_level,
            last_nudge_at: now,
            stale_since: entry.stale_since
          })
        else
          acc
        end
      end)

    # Clean up entries for sessions that are no longer stale
    stale_ids = MapSet.new(stale_agents, fn a -> a[:session_id] || a[:agent_id] end)

    escalations =
      escalations
      |> Enum.filter(fn {sid, _} -> MapSet.member?(stale_ids, sid) end)
      |> Map.new()

    %{state | escalations: escalations}
  end

  defp execute_escalation(session_id, agent, level) do
    agent_name = agent[:name] || agent[:short_name] || String.slice(session_id, 0, 8)

    case level do
      0 ->
        Logger.warning("NudgeEscalator: Agent #{agent_name} (#{session_id}) is stale (level 0: warn)")

        Phoenix.PubSub.broadcast(
          Observatory.PubSub,
          "agent:nudge",
          {:nudge_warning, session_id, agent_name, 0}
        )

      1 ->
        Logger.warning("NudgeEscalator: Nudging agent #{agent_name} via tmux (level 1)")
        nudge_message = "[Observatory] Are you still working? No activity detected for >#{config(:stale_threshold_sec, @default_stale_threshold)}s. Reply or take action to clear this alert."

        case Tmux.deliver(agent[:tmux_session] || session_id, %{content: nudge_message, from: "observatory", type: :nudge}) do
          :ok -> :ok
          {:error, reason} -> Logger.warning("NudgeEscalator: Tmux nudge failed for #{agent_name}: #{inspect(reason)}")
        end

        Phoenix.PubSub.broadcast(
          Observatory.PubSub,
          "agent:nudge",
          {:nudge_sent, session_id, agent_name, 1}
        )

      2 ->
        Logger.warning("NudgeEscalator: Escalating agent #{agent_name} to HITL pause (level 2)")
        HITLRelay.pause(session_id, session_id, "observatory", "Auto-paused: no activity detected")

        Phoenix.PubSub.broadcast(
          Observatory.PubSub,
          "agent:nudge",
          {:nudge_escalated, session_id, agent_name, 2}
        )

      3 ->
        Logger.warning("NudgeEscalator: Agent #{agent_name} marked as zombie (level 3: terminate)")

        Phoenix.PubSub.broadcast(
          Observatory.PubSub,
          "agent:nudge",
          {:nudge_zombie, session_id, agent_name, 3}
        )

      _ ->
        :ok
    end
  end

  defp config(key, default) do
    Application.get_env(:observatory, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
