defmodule IchorWeb.DashboardNavigationHandlers do
  @moduledoc """
  Cross-view navigation event handlers for the dashboard.
  Handles navigation jumps between different views and sub-tabs.
  """

  require Logger

  def handle_event("restore_view_mode", %{"value" => value}, socket) do
    view_mode = normalize_view_mode(value)

    socket
    |> Phoenix.Component.assign(:view_mode, view_mode)
    |> Phoenix.LiveView.push_event("view_mode_changed", %{view_mode: Atom.to_string(view_mode)})
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

  defp normalize_view_mode("command"), do: :command
  defp normalize_view_mode("activity"), do: :activity
  defp normalize_view_mode("pipeline"), do: :pipeline
  defp normalize_view_mode("forensic"), do: :forensic
  defp normalize_view_mode("control"), do: :control
  defp normalize_view_mode("fleet_command"), do: :command
  defp normalize_view_mode("overview"), do: :command
  defp normalize_view_mode("agents"), do: :command
  defp normalize_view_mode("teams"), do: :command
  defp normalize_view_mode("feed"), do: :activity
  defp normalize_view_mode("timeline"), do: :activity
  defp normalize_view_mode("analytics"), do: :activity
  defp normalize_view_mode("messages"), do: :activity
  defp normalize_view_mode("errors"), do: :activity
  defp normalize_view_mode("tasks"), do: :pipeline
  defp normalize_view_mode("scheduler"), do: :pipeline
  defp normalize_view_mode("protocols"), do: :command
  defp normalize_view_mode("registry"), do: :forensic
  defp normalize_view_mode("god_mode"), do: :control
  defp normalize_view_mode("session_cluster"), do: :control

  defp normalize_view_mode(value) do
    Logger.warning("Unrecognized view_mode: #{inspect(value)}")
    :command
  end

  defp handle_jump_to_timeline(%{"session_id" => sid}, socket) do
    socket
    |> Phoenix.Component.assign(:view_mode, :activity)
    |> Phoenix.Component.assign(:activity_tab, :timeline)
    |> Phoenix.Component.assign(:filter_session_id, sid)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end

  defp handle_jump_to_feed(%{"session_id" => sid}, socket) do
    socket
    |> Phoenix.Component.assign(:view_mode, :activity)
    |> Phoenix.Component.assign(:activity_tab, :feed)
    |> Phoenix.Component.assign(:filter_session_id, sid)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end

  defp handle_jump_to_agents(%{"session_id" => sid}, socket) do
    socket
    |> Phoenix.Component.assign(:view_mode, :command)
    |> Phoenix.Component.assign(:filter_session_id, sid)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end

  defp handle_jump_to_tasks(%{"session_id" => sid}, socket) do
    socket
    |> Phoenix.Component.assign(:view_mode, :pipeline)
    |> Phoenix.Component.assign(:pipeline_tab, :board)
    |> Phoenix.Component.assign(:filter_session_id, sid)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end

  defp handle_select_timeline_event(%{"id" => id}, socket) do
    selected = Enum.find(socket.assigns.events, &(&1.id == id))

    socket
    |> Phoenix.Component.assign(:view_mode, :activity)
    |> Phoenix.Component.assign(:activity_tab, :feed)
    |> Phoenix.Component.assign(:selected_event, selected)
    |> Phoenix.Component.assign(:selected_task, nil)
  end

  defp handle_filter_agent_tasks(%{"session_id" => sid}, socket) do
    socket
    |> Phoenix.Component.assign(:view_mode, :pipeline)
    |> Phoenix.Component.assign(:pipeline_tab, :board)
    |> Phoenix.Component.assign(:filter_session_id, sid)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end

  defp handle_filter_analytics_tool(%{"tool" => tool}, socket) do
    socket
    |> Phoenix.Component.assign(:view_mode, :activity)
    |> Phoenix.Component.assign(:activity_tab, :feed)
    |> Phoenix.Component.assign(:search_feed, tool)
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
  end
end
