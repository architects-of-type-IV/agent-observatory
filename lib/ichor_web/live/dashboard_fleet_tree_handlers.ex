defmodule IchorWeb.DashboardFleetTreeHandlers do
  @moduledoc """
  Handles fleet tree UI events: team collapse, comms filter, agent tracing.
  Each dispatch/3 clause returns the updated socket (caller wraps in {:noreply, ...}).
  """

  import Phoenix.Component, only: [assign: 3]

  def dispatch("toggle_fleet_team", %{"name" => name}, socket) do
    collapsed = socket.assigns.collapsed_fleet_teams

    collapsed =
      if MapSet.member?(collapsed, name),
        do: MapSet.delete(collapsed, name),
        else: MapSet.put(collapsed, name)

    assign(socket, :collapsed_fleet_teams, collapsed)
  end

  def dispatch("set_comms_filter", %{"team" => ""}, socket),
    do: assign(socket, :comms_team_filter, nil)

  def dispatch("set_comms_filter", %{"team" => team_name}, socket) do
    new_filter = if socket.assigns.comms_team_filter == team_name, do: nil, else: team_name
    assign(socket, :comms_team_filter, new_filter)
  end

  def dispatch("trace_agent", %{"agent_id" => agent_id}, socket) do
    current = socket.assigns.comms_agent_filter

    new_filter =
      cond do
        agent_id in current -> List.delete(current, agent_id)
        length(current) >= 2 -> [agent_id]
        true -> current ++ [agent_id]
      end

    socket |> assign(:comms_agent_filter, new_filter) |> assign(:activity_tab, :comms)
  end

  def dispatch("clear_trace", _params, socket), do: assign(socket, :comms_agent_filter, [])
end
