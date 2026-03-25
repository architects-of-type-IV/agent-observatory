defmodule IchorWeb.DashboardInfoHandlers do
  @moduledoc """
  Signal and process message handlers for the dashboard LiveView.
  Debounces recompute to coalesce rapid-fire events within a 100ms window.
  Each dispatch/2 clause returns {:noreply, socket}.
  """

  import Phoenix.Component, only: [assign: 3]
  import IchorWeb.DashboardState, only: [recompute: 1]
  import IchorWeb.DashboardTmuxHandlers, only: [refresh_tmux_panels: 1]
  import IchorWeb.DashboardMessagingHandlers, only: [handle_new_mailbox_message: 2]
  import IchorWeb.DashboardNotificationHandlers, only: [handle_agent_crashed: 4]

  alias Ichor.Factory.Project
  alias Ichor.Infrastructure.{HITLRelay, Tmux}
  alias Ichor.Projector.SignalManager
  alias Ichor.Signals.Message
  alias IchorWeb.{DashboardArchonHandlers, DashboardMesHandlers}

  @max_events 500
  @recompute_debounce_ms 100

  defp schedule_recompute(%{assigns: %{recompute_timer: timer}} = socket) when not is_nil(timer),
    do: socket

  defp schedule_recompute(socket) do
    timer = Process.send_after(self(), :do_recompute, @recompute_debounce_ms)
    assign(socket, :recompute_timer, timer)
  end

  def dispatch(:do_recompute, socket) do
    {:noreply, socket |> assign(:recompute_timer, nil) |> recompute()}
  end

  def dispatch(%Message{name: :new_event, data: %{event: event}}, socket) do
    events = [event | socket.assigns.events] |> Enum.take(@max_events)

    {:noreply,
     socket
     |> assign(:events, events)
     |> assign(:now, DateTime.utc_now())
     |> maybe_refresh_archon_manager()
     |> schedule_recompute()}
  end

  def dispatch(%Message{name: :tasks_updated}, socket),
    do: {:noreply, schedule_recompute(socket)}

  def dispatch(%Message{name: :agent_crashed, data: data}, socket),
    do:
      {:noreply,
       handle_agent_crashed(data.session_id, data[:team_name], 0, socket) |> schedule_recompute()}

  def dispatch(%Message{name: :agent_spawned}, socket),
    do: {:noreply, schedule_recompute(socket)}

  def dispatch(%Message{name: :agent_stopped}, socket),
    do: {:noreply, schedule_recompute(socket)}

  def dispatch(%Message{name: :registry_changed}, socket),
    do: {:noreply, schedule_recompute(socket)}

  def dispatch(%Message{name: :fleet_changed}, socket),
    do: {:noreply, schedule_recompute(socket)}

  def dispatch({:refresh_terminal, session}, socket) do
    case Tmux.capture_pane(session, ansi: true) do
      {:ok, output} ->
        {:noreply,
         socket
         |> assign(:tmux_outputs, Map.put(socket.assigns.tmux_outputs, session, output))
         |> Phoenix.LiveView.push_event("terminal_output", %{session: session, data: output})}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def dispatch(%Message{name: :heartbeat}, %{assigns: %{tmux_panels: [_ | _]}} = socket),
    do: {:noreply, refresh_tmux_panels(socket)}

  def dispatch(%Message{name: :heartbeat}, socket), do: {:noreply, socket}

  def dispatch(%Message{name: :mailbox_message, data: %{message: message}}, socket),
    do: handle_new_mailbox_message(message, socket)

  def dispatch(%Message{name: :pipeline_status, data: %{state_map: state}}, socket) do
    merged = Map.merge(socket.assigns.pipeline_state, state)
    {:noreply, socket |> assign(:pipeline_state, merged) |> maybe_refresh_archon_manager()}
  end

  def dispatch(%Message{name: :protocol_update, data: %{stats_map: stats}}, socket),
    do:
      {:noreply,
       socket
       |> assign(:protocol_stats, stats)
       |> maybe_refresh_archon_manager()}

  def dispatch(%Message{name: :terminal_output, data: %{session_id: sid, output: output}}, socket) do
    case socket.assigns.agent_slideout do
      %{session_id: ^sid} -> {:noreply, assign(socket, :slideout_terminal, output)}
      _ -> {:noreply, socket}
    end
  end

  # HITL: refresh paused_sessions assign
  def dispatch(%Message{name: name}, socket) when name in [:gate_open, :gate_close] do
    paused = HITLRelay.paused_sessions() |> MapSet.new()
    {:noreply, assign(socket, :paused_sessions, paused)}
  rescue
    _ -> {:noreply, socket}
  end

  # Nudge/gate: notifications only -- no data changed, no recompute
  def dispatch(%Message{name: name}, socket)
      when name in [:nudge_warning, :nudge_sent, :nudge_escalated, :nudge_zombie],
      do: {:noreply, maybe_refresh_archon_manager(socket)}

  def dispatch(%Message{name: :gate_passed}, socket),
    do: {:noreply, maybe_refresh_archon_manager(socket)}

  def dispatch(%Message{name: :gate_failed}, socket),
    do: {:noreply, maybe_refresh_archon_manager(socket)}

  @gateway_signals ~w(schema_violation node_state_update dead_letter capability_update topology_snapshot entropy_alert)a

  def dispatch(%Message{name: name}, socket) when name in @gateway_signals,
    do: {:noreply, maybe_refresh_archon_manager(socket)}

  # ADR-026: signal pipeline activations
  def dispatch({:signal_activated, %Ichor.Signals.Signal{} = signal}, socket) do
    {:noreply, socket |> push_signal_toast(signal) |> schedule_recompute()}
  end

  def dispatch({:archon_response, result}, socket),
    do: {:noreply, DashboardArchonHandlers.handle_archon_response(result, socket)}

  def dispatch({:dismiss_toast, id}, socket),
    do: {:noreply, IchorWeb.DashboardToast.dismiss_toast(socket, id)}

  def dispatch(%Message{name: :mes_project_created}, socket) do
    {:noreply, assign(socket, :mes_projects, Project.list_all!())}
  end

  def dispatch(%Message{name: name}, socket)
      when name in [:mes_scheduler_paused, :mes_scheduler_resumed, :mes_cycle_started],
      do:
        {:noreply,
         assign(socket, :mes_scheduler_status, DashboardMesHandlers.fetch_scheduler_status())}

  def dispatch(%Message{name: :mes_plugin_loaded}, socket) do
    {:noreply, assign(socket, :mes_projects, Project.list_all!())}
  end

  def dispatch(%Message{name: name}, socket)
      when name in [
             :mes_cycle_timeout,
             :mes_project_picked_up,
             :mes_research_ingested,
             :mes_research_ingest_failed
           ],
      do: {:noreply, maybe_refresh_archon_manager(socket)}

  def dispatch(%Message{name: name}, socket)
      when name in [
             :project_artifact_created,
             :planning_team_ready,
             :planning_run_complete,
             :planning_team_killed
           ] do
    {:noreply, reload_planning_project(socket)}
  end

  # Catch-all: ignore unknown signals (new signals added to catalog won't crash)
  def dispatch(%Message{}, socket), do: {:noreply, maybe_refresh_archon_manager(socket)}

  defp reload_planning_project(%{assigns: %{selected_mes_project: nil}} = socket), do: socket

  defp reload_planning_project(socket) do
    project =
      case Project.get(socket.assigns.selected_mes_project.id) do
        {:ok, loaded_project} -> loaded_project
        _ -> nil
      end

    assign(socket, :planning_project, project)
  end

  defp maybe_refresh_archon_manager(%{assigns: %{show_archon: true}} = socket) do
    socket
    |> assign(:archon_snapshot, SignalManager.snapshot())
    |> assign(:archon_attention, SignalManager.attention())
  rescue
    _ -> socket
  end

  defp maybe_refresh_archon_manager(socket), do: socket

  defp push_signal_toast(socket, signal) do
    {level, msg} = signal_toast(signal)
    IchorWeb.DashboardToast.push_toast(socket, level, msg)
  end

  defp signal_toast(%Ichor.Signals.Signal{name: "agent.tool.budget"} = s) do
    count = s.metadata[:count]
    limit = s.metadata[:limit]
    key = String.slice(to_string(s.key), 0, 12)
    {:warning, "Budget exhausted — session #{key} (#{count}/#{limit} tools)"}
  end

  defp signal_toast(%Ichor.Signals.Signal{name: "agent.message.protocol"} = s) do
    violations = s.metadata[:violations] || []
    {:error, "Protocol violation — #{s.key}: #{length(violations)} comm rule violation(s)"}
  end

  defp signal_toast(%Ichor.Signals.Signal{name: "agent.entropy"} = s) do
    score = s.metadata[:entropy_score]
    key = String.slice(to_string(s.key), 0, 12)
    {:warning, "Loop detected — session #{key} entropy #{score}"}
  end

  defp signal_toast(%Ichor.Signals.Signal{name: name} = s) do
    {:info, "Signal #{name} — key=#{s.key} events=#{length(s.events)}"}
  end
end
