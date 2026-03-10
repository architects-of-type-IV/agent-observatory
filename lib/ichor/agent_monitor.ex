defmodule Ichor.AgentMonitor do
  @moduledoc """
  Monitors agent health by tracking event activity per session.
  Detects crashed agents (idle >120s without SessionEnd) and broadcasts notifications.
  """
  use GenServer
  require Logger

  alias Ichor.Fleet.AgentProcess
  alias Ichor.Gateway.AgentRegistry
  alias Ichor.Gateway.AgentRegistry.AgentEntry
  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.TaskManager

  @check_interval 5_000
  @crash_threshold_sec 120

  # State: %{session_id => %{last_event_at: DateTime, team_name: string}}
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Ichor.PubSub, "events:stream")
    schedule_check()
    {:ok, %{sessions: %{}}}
  end

  @impl true
  def handle_info({:new_event, event}, state) do
    state = update_session_activity(event, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_crashes, state) do
    schedule_check()
    state = detect_and_handle_crashes(state)
    {:noreply, state}
  end

  # Update session last_event_at timestamp
  defp update_session_activity(event, state) do
    case event.hook_event_type do
      :SessionStart ->
        team_name = extract_team_name(event)

        sessions =
          Map.put(state.sessions, event.session_id, %{
            last_event_at: DateTime.utc_now(),
            team_name: team_name
          })

        %{state | sessions: sessions}

      :SessionEnd ->
        sessions = Map.delete(state.sessions, event.session_id)
        %{state | sessions: sessions}

      _ ->
        touch_session_activity(event.session_id, state)
    end
  end

  defp touch_session_activity(session_id, state) do
    if Map.has_key?(state.sessions, session_id) do
      sessions =
        Map.update!(state.sessions, session_id, &%{&1 | last_event_at: DateTime.utc_now()})

      %{state | sessions: sessions}
    else
      state
    end
  end

  defp detect_and_handle_crashes(state) do
    now = DateTime.utc_now()

    {stale_sessions, active_sessions} =
      state.sessions
      |> Enum.split_with(fn {_session_id, data} ->
        DateTime.diff(now, data.last_event_at, :second) > @crash_threshold_sec
      end)

    # Only declare crash if the agent is actually dead (no tmux session, no BEAM process)
    {crashed, still_alive} =
      Enum.split_with(stale_sessions, fn {session_id, _data} ->
        not agent_alive?(session_id)
      end)

    Enum.each(crashed, fn {session_id, data} ->
      handle_crash(session_id, data.team_name)
    end)

    # Keep still-alive stale sessions in tracking (agent is alive, just idle)
    %{state | sessions: Map.new(active_sessions ++ still_alive)}
  end

  defp agent_alive?(session_id) do
    AgentProcess.alive?(session_id) or tmux_session_alive?(session_id)
  end

  defp tmux_session_alive?(session_id) do
    registry_entry = AgentRegistry.get(session_id)
    tmux_target = registry_entry && registry_entry.channels && registry_entry.channels.tmux

    case tmux_target do
      nil -> false
      target -> Tmux.available?(target)
    end
  rescue
    _ -> false
  end

  defp handle_crash(session_id, team_name) do
    team_label = team_name || "standalone"
    Logger.warning("AgentMonitor: Detected crash for session #{session_id} (#{team_label})")

    # Reassign tasks if team exists
    reassigned_count =
      if team_name do
        reassign_agent_tasks(session_id, team_name)
      else
        0
      end

    # Broadcast crash event
    Ichor.Signal.emit(:agent_crashed, %{
      session_id: session_id,
      team_name: team_name
    })

    # Write inbox notification
    write_inbox_notification(session_id, team_name, reassigned_count)
  end

  defp reassign_agent_tasks(session_id, team_name) do
    tasks = TaskManager.list_tasks(team_name)

    # Find tasks owned by crashed agent
    owned_tasks =
      Enum.filter(tasks, fn task ->
        task["status"] == "in_progress" and task["owner"] == session_id
      end)

    # Reset to pending status and count successes
    owned_tasks
    |> Enum.map(fn task ->
      case TaskManager.update_task(team_name, task["id"], %{
             "status" => "pending",
             "owner" => nil
           }) do
        {:ok, _} ->
          Logger.info(
            "AgentMonitor: Reassigned task #{task["id"]} from crashed agent #{session_id}"
          )

          1

        {:error, reason} ->
          Logger.error("AgentMonitor: Failed to reassign task #{task["id"]}: #{inspect(reason)}")
          0
      end
    end)
    |> Enum.sum()
  end

  defp extract_team_name(event) do
    # Try to extract team name from payload
    case event.payload do
      %{"team_name" => team_name} when is_binary(team_name) -> team_name
      _ -> nil
    end
  end

  defp schedule_check do
    Process.send_after(self(), :check_crashes, @check_interval)
  end

  defp write_inbox_notification(session_id, team_name, reassigned_count) do
    return_if_no_team(team_name)

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
        Logger.info("AgentMonitor: Wrote crash notification to inbox for #{session_id}")

      {:error, reason} ->
        Logger.error("AgentMonitor: Failed to write inbox notification: #{inspect(reason)}")
    end
  end

  defp return_if_no_team(nil), do: :ok
  defp return_if_no_team(_), do: nil
end
