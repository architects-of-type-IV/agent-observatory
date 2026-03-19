defmodule IchorWeb.DashboardNavigationHandlers do
  @moduledoc """
  Cross-view navigation event handlers for the dashboard.
  Handles navigation jumps between different views and sub-tabs.
  """

  alias IchorWeb.DashboardViewRouter

  def handle_event("restore_view_mode", %{"value" => value}, socket) do
    DashboardViewRouter.assign_view(socket, value)
  end

  def handle_event("jump_to_timeline", params, socket),
    do: handle_jump_to_timeline(params, socket)

  def handle_event("jump_to_feed", params, socket), do: handle_jump_to_feed(params, socket)
  def handle_event("jump_to_agents", params, socket), do: handle_jump_to_agents(params, socket)
  def handle_event("jump_to_tasks", params, socket), do: handle_jump_to_tasks(params, socket)

  def handle_event("select_timeline_event", params, socket),
    do: handle_select_timeline_event(params, socket)

  def handle_event("filter_agent_tasks", params, socket),
    do: handle_filter_agent_tasks(params, socket)

  def handle_event("filter_analytics_tool", params, socket),
    do: handle_filter_analytics_tool(params, socket)

  defp handle_jump_to_timeline(%{"session_id" => sid}, socket) do
    socket
    |> DashboardViewRouter.assign_view("timeline")
    |> Phoenix.Component.assign(:filter_session_id, sid)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end

  defp handle_jump_to_feed(%{"session_id" => sid}, socket) do
    socket
    |> DashboardViewRouter.assign_view("feed")
    |> Phoenix.Component.assign(:filter_session_id, sid)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end

  defp handle_jump_to_agents(%{"session_id" => sid}, socket) do
    socket
    |> DashboardViewRouter.assign_view("agents")
    |> Phoenix.Component.assign(:filter_session_id, sid)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end

  defp handle_jump_to_tasks(%{"session_id" => sid}, socket) do
    socket
    |> DashboardViewRouter.assign_view("tasks")
    |> Phoenix.Component.assign(:filter_session_id, sid)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end

  defp handle_select_timeline_event(%{"id" => id}, socket) do
    selected = Enum.find(socket.assigns.events, &(&1.id == id))

    socket
    |> DashboardViewRouter.assign_view("feed")
    |> Phoenix.Component.assign(:selected_event, selected)
    |> Phoenix.Component.assign(:selected_task, nil)
  end

  defp handle_filter_agent_tasks(%{"session_id" => sid}, socket) do
    socket
    |> DashboardViewRouter.assign_view("tasks")
    |> Phoenix.Component.assign(:filter_session_id, sid)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end

  defp handle_filter_analytics_tool(%{"tool" => tool}, socket) do
    socket
    |> DashboardViewRouter.assign_view("feed")
    |> Phoenix.Component.assign(:search_feed, tool)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end
end
