defmodule ObservatoryWeb.DashboardNavigationHandlers do
  @moduledoc """
  Cross-view navigation event handlers for the dashboard.
  Handles navigation jumps between different views (Feed, Timeline, Agents, etc).

  Usage: defdelegate handle_event(event, params, socket), to: ObservatoryWeb.DashboardNavigationHandlers
  """

  require Logger

  def handle_event("restore_view_mode", %{"value" => value}, socket) do
    view_mode =
      case value do
        "fleet_command" -> :fleet_command
        "session_cluster" -> :session_cluster
        "registry" -> :registry
        "scheduler" -> :scheduler
        "forensic" -> :forensic
        "god_mode" -> :god_mode
        _ ->
          Logger.warning("Unrecognized view_mode: #{inspect(value)}")
          :fleet_command
      end

    socket
    |> Phoenix.Component.assign(:view_mode, view_mode)
    |> Phoenix.LiveView.push_event("view_mode_changed", %{view_mode: value})
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
    |> Phoenix.Component.assign(:view_mode, :timeline)
    |> Phoenix.Component.assign(:filter_session_id, sid)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end

  defp handle_jump_to_feed(%{"session_id" => sid}, socket) do
    socket
    |> Phoenix.Component.assign(:view_mode, :feed)
    |> Phoenix.Component.assign(:filter_session_id, sid)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end

  defp handle_jump_to_agents(%{"session_id" => sid}, socket) do
    socket
    |> Phoenix.Component.assign(:view_mode, :agents)
    |> Phoenix.Component.assign(:filter_session_id, sid)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end

  defp handle_jump_to_tasks(%{"session_id" => sid}, socket) do
    socket
    |> Phoenix.Component.assign(:view_mode, :tasks)
    |> Phoenix.Component.assign(:filter_session_id, sid)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end

  defp handle_select_timeline_event(%{"id" => id}, socket) do
    # Find event in the full list and switch to feed view with it selected
    selected = Enum.find(socket.assigns.events, &(&1.id == id))

    socket
    |> Phoenix.Component.assign(:view_mode, :feed)
    |> Phoenix.Component.assign(:selected_event, selected)
    |> Phoenix.Component.assign(:selected_task, nil)
  end

  defp handle_filter_agent_tasks(%{"session_id" => sid}, socket) do
    socket
    |> Phoenix.Component.assign(:view_mode, :tasks)
    |> Phoenix.Component.assign(:filter_session_id, sid)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end

  defp handle_filter_analytics_tool(%{"tool" => tool}, socket) do
    socket
    |> Phoenix.Component.assign(:view_mode, :feed)
    |> Phoenix.Component.assign(:search_feed, tool)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end
end
