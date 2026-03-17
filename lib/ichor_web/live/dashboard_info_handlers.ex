defmodule IchorWeb.DashboardInfoHandlers do
  @moduledoc """
  Signal and process message handlers for the dashboard LiveView.
  Each dispatch/2 clause returns {:noreply, socket}.

  Uses debounced recompute to coalesce rapid-fire events (e.g. multiple agents
  sending events within the same 100ms window) into a single recompute cycle.
  """

  import Phoenix.Component, only: [assign: 3]
  import IchorWeb.DashboardState, only: [recompute: 1]
  import IchorWeb.DashboardTmuxHandlers, only: [refresh_tmux_panels: 1]
  import IchorWeb.DashboardMessagingHandlers, only: [handle_new_mailbox_message: 2]
  import IchorWeb.DashboardNotificationHandlers, only: [handle_agent_crashed: 4]
  import IchorWeb.DashboardGatewayHandlers, only: [handle_gateway_info: 2]

  alias Ichor.Gateway.HITLRelay

  alias Ichor.Mes.{Project, Scheduler}
  alias Ichor.Signals.Message
  alias IchorWeb.DashboardArchonHandlers

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
     socket |> assign(:events, events) |> assign(:now, DateTime.utc_now()) |> schedule_recompute()}
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

  def dispatch(%Message{name: :swarm_state, data: %{state_map: state}}, socket),
    do: {:noreply, assign(socket, :swarm_state, state)}

  def dispatch(%Message{name: :protocol_update, data: %{stats_map: stats}}, socket),
    do: {:noreply, socket |> assign(:protocol_stats, stats) |> assign(:dirty, true)}

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
      do: {:noreply, socket}

  def dispatch(%Message{name: :gate_passed}, socket), do: {:noreply, socket}
  def dispatch(%Message{name: :gate_failed}, socket), do: {:noreply, socket}

  # ── Signal-native: gateway signals ─────────────────────────────────────

  def dispatch(%Message{name: :decision_log} = sig, socket),
    do: {:noreply, handle_gateway_info(sig, socket)}

  def dispatch(%Message{name: :schema_violation} = sig, socket),
    do: {:noreply, handle_gateway_info(sig, socket)}

  def dispatch(%Message{name: :node_state_update} = sig, socket),
    do: {:noreply, handle_gateway_info(sig, socket)}

  def dispatch(%Message{name: :dead_letter} = sig, socket),
    do: {:noreply, handle_gateway_info(sig, socket)}

  def dispatch(%Message{name: :capability_update} = sig, socket),
    do: {:noreply, handle_gateway_info(sig, socket)}

  def dispatch(%Message{name: :topology_snapshot} = sig, socket),
    do: {:noreply, handle_gateway_info(sig, socket)}

  def dispatch(%Message{name: :entropy_alert} = sig, socket),
    do: {:noreply, handle_gateway_info(sig, socket)}

  def dispatch(%Message{name: :dag_delta} = sig, socket),
    do: {:noreply, handle_gateway_info(sig, socket)}

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
      when name in [:mes_scheduler_paused, :mes_scheduler_resumed, :mes_cycle_started] do
    status =
      try do
        Scheduler.status()
      catch
        :exit, _ -> %{tick: 0, active_runs: 0, next_tick_in: 60_000, paused: false}
      end

    {:noreply, assign(socket, :mes_scheduler_status, status)}
  end

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
      do: {:noreply, socket}

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
  def dispatch(%Message{}, socket), do: {:noreply, socket}

  # ── Private ─────────────────────────────────────────────────────────

  @genesis_loads [:adrs, :features, :use_cases, :checkpoints, :conversations, :phases]

  defp reload_genesis_node(%{assigns: %{selected_mes_project: nil}} = socket), do: socket

  defp reload_genesis_node(socket) do
    node =
      case Ichor.Genesis.Node.by_project(socket.assigns.selected_mes_project.id,
             load: @genesis_loads
           ) do
        {:ok, [n | _]} -> n
        _ -> nil
      end

    assign(socket, :genesis_node, node)
  end
end
