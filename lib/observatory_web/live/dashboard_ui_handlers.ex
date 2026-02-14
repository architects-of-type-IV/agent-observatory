defmodule ObservatoryWeb.DashboardUIHandlers do
  @moduledoc """
  UI interaction handlers for keyboard shortcuts, modal toggles, and detail panel management.
  """

  def handle_toggle_shortcuts_help(_params, socket) do
    socket |> Phoenix.Component.assign(:show_shortcuts_help, !socket.assigns.show_shortcuts_help)
  end

  def handle_toggle_create_task_modal(_params, socket) do
    socket |> Phoenix.Component.assign(:show_create_task_modal, !socket.assigns.show_create_task_modal)
  end

  def handle_close_detail(_params, socket) do
    socket |> Phoenix.Component.assign(:selected_event, nil)
  end

  def handle_close_task_detail(_params, socket) do
    socket |> Phoenix.Component.assign(:selected_task, nil)
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

      new_event = case direction do
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
        _ -> current
      end

      socket |> Phoenix.Component.assign(:selected_event, new_event)
    else
      socket
    end
  end
end
