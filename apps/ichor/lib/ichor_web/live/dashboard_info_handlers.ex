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
  import IchorWeb.DashboardGatewayHandlers, only: [handle_gateway_info: 2]

  alias Ichor.Archon.SignalManager
  alias Ichor.Gateway.HITLRelay
  alias Ichor.Mes.Project
  alias Ichor.Signals.Message
  alias IchorWeb.{DashboardArchonHandlers, DashboardMesHandlers}

  @max_events 500
  @recompute_debounce_ms 100

  # ── Debounced recompute ──────────────────────────────────────────────

  defp schedule_recompute(%{assigns: %{recompute_timer: timer}} = socket) when not is_nil(timer),
    do: socket

  defp schedule_recompute(socket) do
    timer = Process.send_after(self(), :do_recompute, @recompute_debounce_ms)
    assign(socket, :recompute_timer, timer)
  end

  def dispatch(:do_recompute, socket) do
    {:noreply, socket |> assign(:recompute_timer, nil) |> recompute()}
  end

  # ── Signal-native: data-changing events ────────────────────────────────

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

  # ── Signal-native: lightweight events ──────────────────────────────────

  def dispatch(%Message{name: :heartbeat}, %{assigns: %{tmux_panels: [_ | _]}} = socket),
    do: {:noreply, refresh_tmux_panels(socket)}

  def dispatch(%Message{name: :heartbeat}, socket), do: {:noreply, socket}

  def dispatch(%Message{name: :mailbox_message, data: %{message: message}}, socket),
    do: handle_new_mailbox_message(message, socket)

  def dispatch(%Message{name: :dag_status, data: %{state_map: state}}, socket),
    do:
      {:noreply,
       socket
       |> assign(:dag_state, state)
       |> maybe_refresh_archon_manager()}

  def dispatch(%Message{name: :protocol_update, data: %{stats_map: stats}}, socket),
    do:
      {:noreply,
       socket
       |> assign(:protocol_stats, stats)
       |> assign(:dirty, true)
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

  @gateway_signals ~w(decision_log schema_violation node_state_update dead_letter capability_update topology_snapshot entropy_alert dag_delta)a

  def dispatch(%Message{name: name} = sig, socket) when name in @gateway_signals,
    do: {:noreply, handle_gateway_info(sig, socket) |> maybe_refresh_archon_manager()}

  # ── Non-signal messages ────────────────────────────────────────────────

  def dispatch({:archon_response, result}, socket),
    do: {:noreply, DashboardArchonHandlers.handle_archon_response(result, socket)}

  def dispatch({:dismiss_toast, id}, socket),
    do: {:noreply, IchorWeb.DashboardToast.dismiss_toast(socket, id)}

  # ── Signal-native: MES signals ─────────────────────────────────────

  def dispatch(%Message{name: :mes_project_created}, socket) do
    {:noreply, assign(socket, :mes_projects, Project.list_all!())}
  end

  def dispatch(%Message{name: name}, socket)
      when name in [:mes_scheduler_paused, :mes_scheduler_resumed, :mes_cycle_started],
      do:
        {:noreply,
         assign(socket, :mes_scheduler_status, DashboardMesHandlers.fetch_scheduler_status())}

  def dispatch(%Message{name: :mes_subsystem_loaded}, socket) do
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

  # ── Signal-native: Genesis signals ─────────────────────────────────

  def dispatch(%Message{name: name}, socket)
      when name in [
             :genesis_artifact_created,
             :genesis_team_ready,
             :genesis_run_complete,
             :genesis_team_killed
           ] do
    {:noreply, reload_genesis_node(socket)}
  end

  # Catch-all: ignore unknown signals (new signals added to catalog won't crash)
  def dispatch(%Message{}, socket), do: {:noreply, maybe_refresh_archon_manager(socket)}

  # ── Private ─────────────────────────────────────────────────────────

  @genesis_loads [
    :adrs,
    :features,
    :use_cases,
    :checkpoints,
    :conversations,
    phases: [sections: [tasks: [:subtasks]]]
  ]

  defp reload_genesis_node(%{assigns: %{selected_mes_project: nil}} = socket), do: socket

  defp reload_genesis_node(socket) do
    node =
      case Ichor.Genesis.node_by_project(socket.assigns.selected_mes_project.id,
             load: @genesis_loads
           ) do
        {:ok, [n | _]} -> n
        _ -> nil
      end

    assign(socket, :genesis_node, node)
  end

  defp maybe_refresh_archon_manager(%{assigns: %{show_archon: true}} = socket) do
    socket
    |> assign(:archon_snapshot, SignalManager.snapshot())
    |> assign(:archon_attention, SignalManager.attention())
  rescue
    _ -> socket
  end

  defp maybe_refresh_archon_manager(socket), do: socket
end
