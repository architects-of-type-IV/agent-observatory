defmodule ObservatoryWeb.DashboardInfoHandlers do
  @moduledoc """
  PubSub and process message handlers for the dashboard LiveView.
  Each dispatch/2 clause returns {:noreply, socket}.
  """

  import Phoenix.Component, only: [assign: 3]
  import ObservatoryWeb.DashboardState, only: [recompute: 1]
  import ObservatoryWeb.DashboardTmuxHandlers, only: [refresh_tmux_panels: 1]
  import ObservatoryWeb.DashboardMessagingHandlers, only: [handle_new_mailbox_message: 2]
  import ObservatoryWeb.DashboardNotificationHandlers, only: [handle_agent_crashed: 4]
  import ObservatoryWeb.DashboardGatewayHandlers, only: [handle_gateway_info: 2]

  alias ObservatoryWeb.DashboardArchonHandlers

  @max_events 500

  def dispatch({:new_event, event}, socket) do
    events = [event | socket.assigns.events] |> Enum.take(@max_events)
    {:noreply, socket |> assign(:events, events) |> assign(:now, DateTime.utc_now()) |> recompute()}
  end

  def dispatch({:heartbeat, _count}, socket) do
    socket =
      if socket.assigns.tmux_panels != [] do
        refresh_tmux_panels(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  def dispatch({:teams_updated, teams}, socket) do
    disk_teams = if is_map(teams), do: teams, else: %{}

    team_names =
      disk_teams |> Map.values() |> Enum.map(fn t -> t[:name] || t["name"] end) |> MapSet.new()

    pruned =
      Enum.filter(socket.assigns.inspected_teams, fn t -> MapSet.member?(team_names, t.name) end)

    {:noreply,
     socket |> assign(:disk_teams, disk_teams) |> assign(:inspected_teams, pruned) |> recompute()}
  end

  def dispatch({:new_mailbox_message, message}, socket),
    do: handle_new_mailbox_message(message, socket)

  def dispatch({:swarm_state, state}, socket),
    do: {:noreply, socket |> assign(:swarm_state, state) |> recompute()}

  def dispatch({:protocol_update, stats}, socket),
    do: {:noreply, socket |> assign(:protocol_stats, stats) |> assign(:dirty, true)}

  def dispatch({:message_read, _}, socket),
    do:
      {:noreply,
       socket
       |> assign(:protocol_stats, Observatory.ProtocolTracker.get_stats())
       |> assign(:dirty, true)}

  def dispatch({:agent_crashed, sid, team, count}, socket),
    do: {:noreply, handle_agent_crashed(sid, team, count, socket) |> recompute()}

  def dispatch({:terminal_output, session_id, output}, socket) do
    if socket.assigns.agent_slideout && socket.assigns.agent_slideout[:session_id] == session_id do
      {:noreply, assign(socket, :slideout_terminal, output)}
    else
      {:noreply, socket}
    end
  end

  def dispatch({:hitl, _event}, socket), do: {:noreply, recompute(socket)}

  def dispatch({nudge_type, _sid, _name, _level}, socket)
      when nudge_type in [:nudge_warning, :nudge_sent, :nudge_escalated, :nudge_zombie],
      do: {:noreply, recompute(socket)}

  def dispatch({gate_type, _sid, _task_id, _cmd}, socket)
      when gate_type in [:gate_passed],
      do: {:noreply, recompute(socket)}

  def dispatch({:gate_failed, _sid, _task_id, _cmd, _output}, socket),
    do: {:noreply, recompute(socket)}

  def dispatch({:agent_spawned, _id, _name, _cap}, socket),
    do: {:noreply, recompute(socket)}

  def dispatch(:registry_changed, socket),
    do: {:noreply, recompute(socket)}

  # Gateway PubSub
  def dispatch(msg, socket) when is_tuple(msg) and elem(msg, 0) in [
    :decision_log, :schema_violation, :node_state_update, :dead_letter, :capability_update
  ] do
    {:noreply, handle_gateway_info(msg, socket) |> recompute()}
  end

  def dispatch(%{event_type: "entropy_alert"} = msg, socket),
    do: {:noreply, handle_gateway_info(msg, socket) |> recompute()}

  def dispatch(%{session_id: _sid, state: _state} = msg, socket)
      when map_size(msg) == 2,
      do: {:noreply, handle_gateway_info(msg, socket) |> recompute()}

  def dispatch(%{nodes: _nodes, edges: _edges} = msg, socket),
    do: {:noreply, handle_gateway_info(msg, socket)}

  def dispatch(%{event: "dag_delta"} = msg, socket),
    do: {:noreply, handle_gateway_info(msg, socket)}

  def dispatch({:archon_response, result}, socket),
    do: {:noreply, DashboardArchonHandlers.handle_archon_response(result, socket)}
end
