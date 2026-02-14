defmodule ObservatoryWeb.DashboardNavigationHandlers do
  @moduledoc """
  Cross-view navigation event handlers for the dashboard.
  Handles navigation jumps between different views (Feed, Timeline, Agents, etc).
  """

  def handle_jump_to_timeline(%{"session_id" => sid}, socket) do
    {:noreply,
     socket
     |> Phoenix.Component.assign(:view_mode, :timeline)
     |> Phoenix.Component.assign(:filter_session_id, sid)
     |> Phoenix.Component.assign(:selected_event, nil)
     |> Phoenix.Component.assign(:selected_task, nil)}
  end

  def handle_jump_to_feed(%{"session_id" => sid}, socket) do
    {:noreply,
     socket
     |> Phoenix.Component.assign(:view_mode, :feed)
     |> Phoenix.Component.assign(:filter_session_id, sid)
     |> Phoenix.Component.assign(:selected_event, nil)
     |> Phoenix.Component.assign(:selected_task, nil)}
  end

  def handle_jump_to_agents(%{"session_id" => sid}, socket) do
    {:noreply,
     socket
     |> Phoenix.Component.assign(:view_mode, :agents)
     |> Phoenix.Component.assign(:filter_session_id, sid)
     |> Phoenix.Component.assign(:selected_event, nil)
     |> Phoenix.Component.assign(:selected_task, nil)}
  end

  def handle_jump_to_tasks(%{"session_id" => sid}, socket) do
    {:noreply,
     socket
     |> Phoenix.Component.assign(:view_mode, :tasks)
     |> Phoenix.Component.assign(:filter_session_id, sid)
     |> Phoenix.Component.assign(:selected_event, nil)
     |> Phoenix.Component.assign(:selected_task, nil)}
  end

  def handle_select_timeline_event(%{"id" => id}, socket) do
    # Find event in the full list and switch to feed view with it selected
    selected = Enum.find(socket.assigns.events, &(&1.id == id))

    {:noreply,
     socket
     |> Phoenix.Component.assign(:view_mode, :feed)
     |> Phoenix.Component.assign(:selected_event, selected)
     |> Phoenix.Component.assign(:selected_task, nil)}
  end

  def handle_filter_agent_tasks(%{"session_id" => sid}, socket) do
    {:noreply,
     socket
     |> Phoenix.Component.assign(:view_mode, :tasks)
     |> Phoenix.Component.assign(:filter_session_id, sid)
     |> Phoenix.Component.assign(:selected_event, nil)
     |> Phoenix.Component.assign(:selected_task, nil)}
  end

  def handle_filter_analytics_tool(%{"tool" => tool}, socket) do
    {:noreply,
     socket
     |> Phoenix.Component.assign(:view_mode, :feed)
     |> Phoenix.Component.assign(:search_feed, tool)
     |> Phoenix.Component.assign(:selected_event, nil)
     |> Phoenix.Component.assign(:selected_task, nil)}
  end
end
