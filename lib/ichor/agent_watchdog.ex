defmodule Ichor.AgentWatchdog do
  @moduledoc """
  Consolidated agent health monitor. Replaces Heartbeat, AgentMonitor,
  NudgeEscalator, and PaneMonitor with a single GenServer and one timer.

  On every :beat (5s):
    1. Emit heartbeat signal
    2. Detect and handle crashed agents
    3. Advance escalation for stale agents
    4. Scan tmux panes for DONE/BLOCKED signals

  Subscribes to :events to keep session activity current.
  """
  use GenServer
  require Logger

  alias Ichor.AgentWatchdog.{EventState, NudgePolicy, PaneParser}
  alias Ichor.Control.AgentProcess
  alias Ichor.Gateway.AgentRegistry.AgentEntry
  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.Gateway.HITLRelay
  alias Ichor.Messages.Bus
  alias Ichor.Signals.Message
  alias Ichor.Tasks.TeamStore

  @interval 5_000
  @crash_threshold_sec 120

  @default_stale_threshold 600
  @default_nudge_interval 300
  @default_max_level 3

  # State shape:
  # %{
  #   count: integer,
  #   sessions: %{session_id => %{last_event_at: DateTime, team_name: string | nil}},
  #   escalations: %{session_id => %{level: integer, last_nudge_at: DateTime, stale_since: DateTime}},
  #   captures: %{tmux_target => string},
  #   signals: %{{session_id, :done | :blocked} => string}
  # }

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Ichor.Signals.subscribe(:events)
    schedule()

    {:ok,
     %{
       count: 0,
       sessions: %{},
       escalations: %{},
       captures: %{},
       signals: %{}
     }}
  end

  @impl true
  def handle_info(:beat, state) do
    next = state.count + 1

    Ichor.Signals.emit(:heartbeat, %{count: next})

    state =
      state
      |> Map.put(:count, next)
      |> detect_and_handle_crashes()
      |> run_escalation_check()
      |> scan_all_panes()

    schedule()
    {:noreply, state}
  end

  @impl true
  def handle_info(%Message{name: :new_event, data: %{event: event}}, state) do
    sessions = EventState.update_session_activity(event, state.sessions)
    escalations = clear_escalation_if_active(event.session_id, state.escalations)
    {:noreply, %{state | sessions: sessions, escalations: escalations}}
  end

  @impl true
  def handle_info(%Message{}, state), do: {:noreply, state}

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp detect_and_handle_crashes(state) do
    now = DateTime.utc_now()

    {stale_sessions, active_sessions} =
      Enum.split_with(state.sessions, fn {_sid, data} ->
        DateTime.diff(now, data.last_event_at, :second) > @crash_threshold_sec
      end)

    {crashed, still_alive} =
      Enum.split_with(stale_sessions, fn {session_id, _data} ->
        not agent_alive?(session_id)
      end)

    Enum.each(crashed, fn {session_id, data} ->
      handle_crash(session_id, data.team_name)
    end)

    %{state | sessions: Map.new(active_sessions ++ still_alive)}
  end

  defp agent_alive?(session_id) do
    AgentProcess.alive?(session_id) or tmux_session_alive?(session_id)
  end

  defp tmux_session_alive?(session_id) do
    tmux_target =
      case AgentProcess.lookup(session_id) do
        {_pid, %{channels: %{tmux: target}}} when is_binary(target) -> target
        _ -> nil
      end

    case tmux_target do
      nil -> false
      target -> Tmux.available?(target)
    end
  rescue
    _ -> false
  end

  defp handle_crash(session_id, nil) do
    Logger.warning("AgentWatchdog: Detected crash for session #{session_id} (standalone)")
    Ichor.Signals.emit(:agent_crashed, %{session_id: session_id, team_name: nil})
  end

  defp handle_crash(session_id, team_name) do
    Logger.warning("AgentWatchdog: Detected crash for session #{session_id} (#{team_name})")
    reassigned_count = reassign_agent_tasks(session_id, team_name)
    Ichor.Signals.emit(:agent_crashed, %{session_id: session_id, team_name: team_name})
    write_inbox_notification(session_id, team_name, reassigned_count)
  end

  defp reassign_agent_tasks(session_id, team_name) do
    tasks = TeamStore.list_tasks(team_name)

    tasks
    |> Enum.filter(fn task ->
      task["status"] == "in_progress" and task["owner"] == session_id
    end)
    |> Enum.map(fn task ->
      case TeamStore.update_task(team_name, task["id"], %{"status" => "pending", "owner" => nil}) do
        {:ok, _} ->
          Logger.info("AgentWatchdog: Reassigned task #{task["id"]} from #{session_id}")
          1

        {:error, reason} ->
          Logger.error("AgentWatchdog: Failed to reassign task #{task["id"]}: #{inspect(reason)}")
          0
      end
    end)
    |> Enum.sum()
  end

  defp write_inbox_notification(session_id, team_name, reassigned_count) do
    inbox_dir = Path.expand("~/.claude/inbox")
    File.mkdir_p(inbox_dir)

    short_sid = AgentEntry.short_id(session_id)
    timestamp = System.system_time(:millisecond)
    filename = "crash_#{team_name}_#{short_sid}_#{timestamp}.json"

    message = %{
      "type" => "agent_crash",
      "session_id" => session_id,
      "team_name" => team_name,
      "reassigned_tasks" => reassigned_count,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case Jason.encode(message, pretty: true) do
      {:ok, json} ->
        File.write(Path.join(inbox_dir, filename), json)
        Logger.info("AgentWatchdog: Wrote crash notification to inbox for #{session_id}")

      {:error, reason} ->
        Logger.error("AgentWatchdog: Failed to write inbox notification: #{inspect(reason)}")
    end
  end

  defp run_escalation_check(state) do
    now = DateTime.utc_now()
    stale_threshold = config(:stale_threshold_sec, @default_stale_threshold)
    nudge_interval = config(:nudge_interval_sec, @default_nudge_interval)
    max_level = config(:max_level, @default_max_level)

    stale_agents =
      AgentProcess.list_all()
      |> Enum.map(fn {_id, meta} -> meta end)
      |> Enum.reject(&(&1[:role] == :operator))
      |> Enum.filter(&NudgePolicy.stale?(&1, now, stale_threshold))

    stale_ids = MapSet.new(stale_agents, &NudgePolicy.agent_session_id/1)

    escalations =
      NudgePolicy.process_escalations(
        stale_agents,
        state.escalations,
        now,
        nudge_interval,
        max_level,
        &execute_escalation/3
      )

    pruned =
      escalations
      |> Enum.filter(fn {sid, _} -> MapSet.member?(stale_ids, sid) end)
      |> Map.new()

    %{state | escalations: pruned}
  end

  defp clear_escalation_if_active(session_id, escalations) do
    case Map.pop(escalations, session_id) do
      {nil, _} ->
        escalations

      {entry, rest} ->
        maybe_unpause(session_id, entry)
        rest
    end
  end

  defp maybe_unpause(_session_id, %{level: level}) when level < 2, do: :ok

  defp maybe_unpause(session_id, _entry) do
    {:ok, _} = HITLRelay.unpause(session_id, session_id, "ichor-auto")
    :ok
  end

  defp execute_escalation(session_id, agent, level) do
    agent_name = agent[:name] || agent[:short_name] || AgentEntry.short_id(session_id)
    do_escalate(level, session_id, agent_name)
  end

  defp do_escalate(0, session_id, agent_name) do
    Logger.warning("AgentWatchdog: Agent #{agent_name} (#{session_id}) is stale (level 0)")

    Ichor.Signals.emit(:nudge_warning, %{
      session_id: session_id,
      agent_name: agent_name,
      level: 0
    })
  end

  defp do_escalate(1, session_id, agent_name) do
    Logger.warning("AgentWatchdog: Nudging #{agent_name} via tmux (level 1)")
    threshold = config(:stale_threshold_sec, @default_stale_threshold)

    nudge_message =
      "[Ichor] Are you still working? No activity detected for >#{threshold}s. " <>
        "Reply or take action to clear this alert."

    case Bus.send(%{
           from: "ichor",
           to: session_id,
           content: nudge_message,
           type: :nudge
         }) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("AgentWatchdog: Nudge failed for #{agent_name}: #{inspect(reason)}")
    end

    Ichor.Signals.emit(:nudge_sent, %{session_id: session_id, agent_name: agent_name, level: 1})
  end

  defp do_escalate(2, session_id, agent_name) do
    Logger.warning("AgentWatchdog: Escalating #{agent_name} to HITL pause (level 2)")
    HITLRelay.pause(session_id, session_id, "ichor", "Auto-paused: no activity detected")

    Ichor.Signals.emit(:nudge_escalated, %{
      session_id: session_id,
      agent_name: agent_name,
      level: 2
    })
  end

  defp do_escalate(3, session_id, agent_name) do
    Logger.warning("AgentWatchdog: Agent #{agent_name} marked zombie (level 3)")

    Ichor.Signals.emit(:nudge_zombie, %{
      session_id: session_id,
      agent_name: agent_name,
      level: 3
    })
  end

  defp do_escalate(_level, _session_id, _agent_name), do: :ok

  defp scan_all_panes(state) do
    AgentProcess.list_all()
    |> Enum.reduce(state, fn
      {_id, %{status: :active} = meta}, acc -> scan_active_agent(meta, acc)
      _, acc -> acc
    end)
  end

  defp scan_active_agent(agent, acc) do
    case PaneParser.resolve_capture_target(agent) do
      {target, capture_fn} -> scan_agent(agent, target, capture_fn, acc)
      nil -> acc
    end
  end

  defp scan_agent(agent, tmux_target, capture_fn, state) do
    case capture_fn.(tmux_target) do
      {:ok, output} ->
        prev_output = Map.get(state.captures, tmux_target, "")
        state = put_in(state.captures[tmux_target], output)
        new_lines = PaneParser.diff_output(prev_output, output)

        if new_lines != "" do
          parse_pane_signals(agent, new_lines, state)
        else
          state
        end

      {:error, _} ->
        state
    end
  end

  defp parse_pane_signals(agent, text, state) do
    state = check_done_signal(agent, text, state)
    state = check_blocked_signal(agent, text, state)
    check_pane_activity(agent, state)
  end

  defp check_done_signal(agent, text, state) do
    case PaneParser.match_done(text) do
      {:ok, summary} ->
        session_id = agent[:session_id] || agent[:id]
        signal_key = {session_id, :done}

        if Map.get(state.signals, signal_key) != summary do
          Logger.info("AgentWatchdog: DONE signal from #{agent[:id]}: #{summary}")
          Ichor.Signals.emit(:agent_done, %{session_id: session_id, summary: summary})
          put_in(state.signals[signal_key], summary)
        else
          state
        end

      :nomatch ->
        state
    end
  end

  defp check_blocked_signal(agent, text, state) do
    case PaneParser.match_blocked(text) do
      {:ok, reason} ->
        session_id = agent[:session_id] || agent[:id]
        signal_key = {session_id, :blocked}

        if Map.get(state.signals, signal_key) != reason do
          Logger.info("AgentWatchdog: BLOCKED signal from #{agent[:id]}: #{reason}")
          Ichor.Signals.emit(:agent_blocked, %{session_id: session_id, reason: reason})
          put_in(state.signals[signal_key], reason)
        else
          state
        end

      :nomatch ->
        state
    end
  end

  defp check_pane_activity(agent, state) do
    case agent[:session_id] || agent[:id] do
      nil -> :ok
      session_id -> AgentProcess.update_fields(session_id, %{last_event_at: DateTime.utc_now()})
    end

    state
  end

  defp config(key, default) do
    Application.get_env(:ichor, __MODULE__, [])
    |> Keyword.get(key, default)
  end

  defp schedule, do: Process.send_after(self(), :beat, @interval)
end
