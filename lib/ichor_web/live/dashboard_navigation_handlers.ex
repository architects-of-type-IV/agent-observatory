defmodule IchorWeb.DashboardNavigationHandlers do
  @moduledoc """
  Cross-view navigation event handlers for the dashboard.
  Handles navigation jumps between different views and sub-tabs.
  """

  alias IchorWeb.DashboardViewRouter

  def handle_event("restore_view_mode", %{"value" => value}, socket) do
    DashboardViewRouter.assign_view(socket, value)
  end

  def handle_event("jump_to_agents", params, socket), do: handle_jump_to_agents(params, socket)

  defp handle_jump_to_agents(%{"session_id" => sid}, socket) do
    socket
    |> DashboardViewRouter.assign_view("command")
    |> Phoenix.Component.assign(:filter_session_id, sid)
    |> Phoenix.Component.assign(:activity_tab, :comms)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end
end
