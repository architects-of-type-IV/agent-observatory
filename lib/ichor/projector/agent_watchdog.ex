defmodule Ichor.Projector.AgentWatchdog do
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

  alias Ichor.Events
  alias Ichor.Events.Event
  alias Ichor.Factory.Board
  alias Ichor.Fleet.AgentProcess
  alias Ichor.Infrastructure.Tmux
  alias Ichor.Operator.Inbox
  alias Ichor.Projector.AgentWatchdog.EscalationEngine
  alias Ichor.Projector.AgentWatchdog.PaneScanner
  alias Ichor.Signals.Bus
  alias Ichor.Workshop.AgentEntry

  @interval 5_000
  @crash_threshold_sec 120

  @default_stale_threshold 600
  @default_nudge_interval 300
  @default_max_level 2

  # State shape:
  # %{
  #   count: integer,
  #   sessions: %{session_id => %{last_event_at: DateTime, team_name: string | nil}},
  #   escalations: %{session_id => %{level: integer, last_nudge_at: DateTime, stale_since: DateTime}},
  #   captures: %{tmux_target => {session_id, string}},
  #   signals: %{{session_id, :done | :blocked} => string}
  # }

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Ichor.Events.subscribe_all()
    schedule()

    cfg = %{
      stale_threshold: config(:stale_threshold_sec, @default_stale_threshold),
      nudge_interval: config(:nudge_interval_sec, @default_nudge_interval),
      max_level: config(:max_level, @default_max_level)
    }

    {:ok,
     %{
       count: 0,
       sessions: %{},
       escalations: %{},
       captures: %{},
       signals: %{},
       cfg: cfg
     }}
  end

  @impl true
  def handle_info(:beat, state) do
    next = state.count + 1

    Events.emit(Event.new("system.heartbeat", nil, %{count: next}))

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
  def handle_info(%Event{topic: "events.hook.ingested", data: %{event: event}}, state) do
    sessions = update_session_activity(event, state.sessions)
    escalations = clear_escalation_if_active(event.session_id, state.escalations)
    {:noreply, %{state | sessions: sessions, escalations: escalations}}
  end

  @impl true
  def handle_info(%Event{topic: "fleet.agent.stopped", data: %{session_id: session_id}}, state)
      when is_binary(session_id) do
    {:noreply, drop_session_state(state, session_id)}
  end

  @impl true
  def handle_info(%Event{topic: "fleet.team.disbanded", data: %{team_name: team_name}}, state)
      when is_binary(team_name) do
    {:noreply, drop_team_state(state, team_name)}
  end

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
    e ->
      Logger.warning("AgentWatchdog: tmux_session_alive? failed for #{session_id}: #{inspect(e)}")
      false
  end

  defp handle_crash(session_id, nil) do
    Logger.warning("AgentWatchdog: Detected crash for session #{session_id} (standalone)")

    Events.emit(Event.new("agent.crashed", session_id, %{session_id: session_id, team_name: nil}))
  end

  defp handle_crash(session_id, team_name) do
    Logger.warning("AgentWatchdog: Detected crash for session #{session_id} (#{team_name})")
    reassigned_count = reassign_agent_tasks(session_id, team_name)

    Events.emit(
      Event.new("agent.crashed", session_id, %{session_id: session_id, team_name: team_name})
    )

    Inbox.write(:agent_crash, %{
      context: team_name,
      session_id: session_id,
      team_name: team_name,
      reassigned_tasks: reassigned_count
    })
  end

  defp reassign_agent_tasks(session_id, team_name) do
    tasks = Board.list_tasks(team_name)

    tasks
    |> Enum.filter(fn task ->
      task["status"] == "in_progress" and task["owner"] == session_id
    end)
    |> Enum.map(fn task ->
      case Board.update_task(team_name, task["id"], %{"status" => "pending", "owner" => nil}) do
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

  defp run_escalation_check(state) do
    now = DateTime.utc_now()

    %{stale_threshold: stale_threshold, nudge_interval: nudge_interval, max_level: max_level} =
      state.cfg

    stale_agents =
      AgentProcess.list_all()
      |> Enum.map(fn {_id, meta} -> meta end)
      |> Enum.reject(&(&1[:role] == :operator))
      |> Enum.filter(&EscalationEngine.stale?(&1, now, stale_threshold))

    stale_ids = MapSet.new(stale_agents, &EscalationEngine.agent_session_id/1)

    escalations =
      EscalationEngine.process_escalations(
        stale_agents,
        state.escalations,
        now,
        nudge_interval,
        max_level,
        &execute_escalation(&1, &2, &3, stale_threshold)
      )

    pruned =
      escalations
      |> Enum.filter(fn {sid, _} -> MapSet.member?(stale_ids, sid) end)
      |> Map.new()

    %{state | escalations: pruned}
  end

  defp clear_escalation_if_active(session_id, escalations) do
    {_, rest} = Map.pop(escalations, session_id)
    rest
  end

  defp execute_escalation(session_id, agent, level, stale_threshold) do
    agent_name = agent[:name] || agent[:short_name] || AgentEntry.short_id(session_id)
    do_escalate(level, session_id, agent_name, stale_threshold)
  end

  defp do_escalate(0, session_id, agent_name, _stale_threshold) do
    Logger.warning("AgentWatchdog: Agent #{agent_name} (#{session_id}) is stale (level 0)")

    Events.emit(
      Event.new(
        "agent.nudge.warning",
        session_id,
        %{
          session_id: session_id,
          agent_name: agent_name,
          level: 0
        }
      )
    )
  end

  defp do_escalate(1, session_id, agent_name, stale_threshold) do
    Logger.warning("AgentWatchdog: Nudging #{agent_name} via tmux (level 1)")

    nudge_message =
      "[Ichor] Are you still working? No activity detected for >#{stale_threshold}s. " <>
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

    Events.emit(
      Event.new(
        "agent.nudge.sent",
        session_id,
        %{session_id: session_id, agent_name: agent_name, level: 1}
      )
    )
  end

  defp do_escalate(2, session_id, agent_name, _stale_threshold) do
    Logger.warning("AgentWatchdog: Agent #{agent_name} marked zombie (level 2)")

    Events.emit(
      Event.new(
        "agent.nudge.zombie",
        session_id,
        %{
          session_id: session_id,
          agent_name: agent_name,
          level: 2
        }
      )
    )
  end

  defp do_escalate(_level, _session_id, _agent_name, _stale_threshold), do: :ok

  defp update_session_activity(%{hook_event_type: :SessionStart} = event, sessions) do
    team_name = extract_team_name(event)

    Map.put(sessions, event.session_id, %{
      last_event_at: DateTime.utc_now(),
      team_name: team_name
    })
  end

  defp update_session_activity(%{hook_event_type: :SessionEnd} = event, sessions) do
    Map.delete(sessions, event.session_id)
  end

  defp update_session_activity(event, sessions) do
    touch_session_activity(event.session_id, sessions)
  end

  defp extract_team_name(%{payload: %{"team_name" => name}}) when is_binary(name), do: name
  defp extract_team_name(_event), do: nil

  defp touch_session_activity(session_id, sessions) do
    case Map.fetch(sessions, session_id) do
      {:ok, entry} -> Map.put(sessions, session_id, %{entry | last_event_at: DateTime.utc_now()})
      :error -> sessions
    end
  end

  defp scan_all_panes(state) do
    AgentProcess.list_all()
    |> Enum.reduce(state, fn
      {_id, %{status: :active} = meta}, acc -> scan_active_agent(meta, acc)
      _, acc -> acc
    end)
  end

  defp scan_active_agent(agent, acc) do
    case PaneScanner.resolve_capture_target(agent) do
      {target, capture_fn} -> scan_agent(agent, target, capture_fn, acc)
      nil -> acc
    end
  end

  @spec session_id(map()) :: String.t() | nil
  defp session_id(agent), do: agent[:session_id] || agent[:id]

  defp scan_agent(agent, tmux_target, capture_fn, state) do
    session_id = session_id(agent)

    case capture_fn.(tmux_target) do
      {:ok, output} ->
        {_prev_session_id, prev_output} = Map.get(state.captures, tmux_target, {session_id, ""})
        state = put_in(state.captures[tmux_target], {session_id, output})
        new_lines = PaneScanner.diff_output(prev_output, output)

        if new_lines != "" do
          parse_pane_signals(agent, new_lines, state)
        else
          state
        end

      {:error, _} ->
        state
    end
  catch
    :error, :emfile ->
      Logger.warning("AgentWatchdog: skipping pane scan due to open file limit")
      state

    :exit, :emfile ->
      Logger.warning("AgentWatchdog: skipping pane scan due to open file limit")
      state
  end

  defp parse_pane_signals(agent, text, state) do
    state =
      check_pane_signal(
        :done,
        &PaneScanner.match_done/1,
        "agent.done",
        :summary,
        agent,
        text,
        state
      )

    state =
      check_pane_signal(
        :blocked,
        &PaneScanner.match_blocked/1,
        "agent.blocked",
        :reason,
        agent,
        text,
        state
      )

    check_pane_activity(agent, state)
  end

  defp check_pane_signal(kind, match_fn, topic, data_key, agent, text, state) do
    case match_fn.(text) do
      {:ok, value} ->
        session_id = session_id(agent)
        signal_key = {session_id, kind}

        case state.signals do
          %{^signal_key => ^value} ->
            state

          _ ->
            Logger.info("AgentWatchdog: #{kind} signal from #{agent[:id]}: #{value}")

            Events.emit(
              Event.new(topic, session_id, Map.put(%{session_id: session_id}, data_key, value))
            )

            put_in(state.signals[signal_key], value)
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

  defp drop_session_state(state, session_id) do
    captures = Map.filter(state.captures, fn {_target, {sid, _output}} -> sid != session_id end)
    signals = Map.filter(state.signals, fn {{sid, _kind}, _value} -> sid != session_id end)

    %{
      state
      | sessions: Map.delete(state.sessions, session_id),
        escalations: Map.delete(state.escalations, session_id),
        captures: captures,
        signals: signals
    }
  end

  defp drop_team_state(state, team_name) do
    session_ids =
      state.sessions
      |> Enum.filter(fn {session_id, data} ->
        data.team_name == team_name or session_id == team_name or
          String.starts_with?(session_id, team_name <> "-")
      end)
      |> Enum.map(&elem(&1, 0))

    Enum.reduce(session_ids, state, &drop_session_state(&2, &1))
  end

  defp config(key, default) do
    Application.get_env(:ichor, __MODULE__, [])
    |> Keyword.get(key, default)
  end

  defp schedule, do: Process.send_after(self(), :beat, @interval)
end
