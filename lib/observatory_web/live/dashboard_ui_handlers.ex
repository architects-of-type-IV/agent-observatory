defmodule ObservatoryWeb.DashboardUIHandlers do
  @moduledoc """
  UI interaction handlers for keyboard shortcuts, modal toggles, and detail panel management.
  """

  def handle_toggle_shortcuts_help(_params, socket) do
    socket |> Phoenix.Component.assign(:show_shortcuts_help, !socket.assigns.show_shortcuts_help)
  end

  def handle_toggle_create_task_modal(_params, socket) do
    socket
    |> Phoenix.Component.assign(:show_create_task_modal, !socket.assigns.show_create_task_modal)
  end

  def handle_close_detail(_params, socket) do
    socket |> Phoenix.Component.assign(:selected_event, nil)
  end

  def handle_close_task_detail(_params, socket) do
    socket |> Phoenix.Component.assign(:selected_task, nil)
  end

  def handle_toggle_event_detail(%{"id" => id}, socket) do
    expanded = socket.assigns[:expanded_events] || []
    new_expanded = if id in expanded, do: List.delete(expanded, id), else: [id | expanded]
    socket |> Phoenix.Component.assign(:expanded_events, new_expanded)
  end

  def handle_focus_agent(%{"session_id" => session_id}, socket) do
    agent = find_agent_by_id(socket.assigns.teams, session_id)

    socket
    |> Phoenix.Component.assign(:view_mode, :agent_focus)
    |> Phoenix.Component.assign(:selected_agent, agent)
  end

  def handle_close_agent_focus(_params, socket) do
    socket |> Phoenix.Component.assign(:view_mode, :agents)
  end

  def handle_keyboard_escape(_params, socket) do
    socket
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
    |> Phoenix.Component.assign(:search_feed, "")
  end

  def handle_keyboard_navigate(%{"direction" => direction}, socket) do
    # Simple implementation: just move selection in feed view
    if socket.assigns.view_mode == :feed && socket.assigns.visible_events != [] do
      current = socket.assigns.selected_event
      events = socket.assigns.visible_events

      new_event =
        case direction do
          "next" ->
            if current do
              idx = Enum.find_index(events, &(&1.id == current.id))
              if idx && idx < length(events) - 1, do: Enum.at(events, idx + 1), else: current
            else
              List.first(events)
            end

          "prev" ->
            if current do
              idx = Enum.find_index(events, &(&1.id == current.id))
              if idx && idx > 0, do: Enum.at(events, idx - 1), else: current
            else
              List.first(events)
            end

          _ ->
            current
        end

      socket |> Phoenix.Component.assign(:selected_event, new_event)
    else
      socket
    end
  end

  def handle_restore_state(params, socket) do
    socket
    |> maybe_restore(:view_mode, params["view_mode"])
    |> maybe_restore(:filter_source_app, params["filter_source_app"])
    |> maybe_restore(:filter_session_id, params["filter_session_id"])
    |> maybe_restore(:filter_event_type, params["filter_event_type"])
    |> maybe_restore(:search_feed, params["search_feed"])
    |> maybe_restore(:search_sessions, params["search_sessions"])
    |> maybe_restore(:selected_team, params["selected_team"])
  end

  defp maybe_restore(socket, _key, nil), do: socket
  defp maybe_restore(socket, _key, ""), do: socket

  defp maybe_restore(socket, :view_mode, value) when is_binary(value) do
    socket
    |> Phoenix.Component.assign(:view_mode, String.to_existing_atom(value))
    |> Phoenix.LiveView.push_event("view_mode_changed", %{view_mode: value})
  rescue
    ArgumentError -> socket
  end

  defp maybe_restore(socket, key, value), do: Phoenix.Component.assign(socket, key, value)

  defp find_agent_by_id(teams, agent_id) do
    teams
    |> Enum.flat_map(& &1.members)
    |> Enum.find(&(&1[:agent_id] == agent_id))
  end
end
