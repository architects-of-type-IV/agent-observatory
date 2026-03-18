defmodule IchorWeb.DashboardUIHandlers do
  @moduledoc """
  UI interaction handlers for keyboard shortcuts, modal toggles, and detail panel management.
  """

  alias IchorWeb.DashboardViewRouter

  def dispatch("toggle_shortcuts_help", p, s), do: handle_toggle_shortcuts_help(p, s)
  def dispatch("toggle_create_task_modal", p, s), do: handle_toggle_create_task_modal(p, s)
  def dispatch("toggle_event_detail", p, s), do: handle_toggle_event_detail(p, s)
  def dispatch("focus_agent", p, s), do: handle_focus_agent(p, s)
  def dispatch("close_agent_focus", p, s), do: handle_close_agent_focus(p, s)
  def dispatch("keyboard_escape", p, s), do: handle_keyboard_escape(p, s)
  def dispatch("keyboard_navigate", p, s), do: handle_keyboard_navigate(p, s)

  def dispatch("toggle_add_project", _p, s) do
    Phoenix.Component.assign(s, :show_add_project, !s.assigns.show_add_project)
  end

  def dispatch("add_project", p, s) do
    IchorWeb.DashboardDagHandlers.handle_add_project(p, s)
    |> Phoenix.Component.assign(:show_add_project, false)
  end

  def dispatch("set_sub_tab", %{"screen" => screen, "tab" => tab}, s) do
    key =
      case screen do
        "activity" -> :activity_tab
        "pipeline" -> :pipeline_tab
        "forensic" -> :forensic_tab
        "control" -> :control_tab
        _ -> nil
      end

    if key, do: Phoenix.Component.assign(s, key, String.to_existing_atom(tab)), else: s
  end

  def dispatch("toggle_sidebar", _p, s) do
    new_val = !s.assigns.sidebar_collapsed

    s
    |> Phoenix.Component.assign(:sidebar_collapsed, new_val)
    |> Phoenix.LiveView.push_event("filters_changed", %{sidebar_collapsed: to_string(new_val)})
  end

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
    socket |> Phoenix.Component.assign(:view_mode, :command)
  end

  def handle_keyboard_escape(_params, socket) do
    socket
    |> Phoenix.Component.assign(:selected_event, nil)
    |> Phoenix.Component.assign(:selected_task, nil)
    |> Phoenix.Component.assign(:search_feed, "")
    |> Phoenix.Component.assign(:show_archon, false)
  end

  def handle_keyboard_navigate(%{"direction" => direction}, socket) do
    if socket.assigns.view_mode == :activity && socket.assigns.visible_events != [] do
      events = socket.assigns.visible_events
      current = socket.assigns.selected_event
      new_event = navigate_event(direction, events, current)
      Phoenix.Component.assign(socket, :selected_event, new_event)
    else
      socket
    end
  end

  defp navigate_event("next", events, nil), do: List.first(events)
  defp navigate_event("prev", events, nil), do: List.first(events)

  defp navigate_event("next", events, current) do
    idx = Enum.find_index(events, &(&1.id == current.id))
    if idx && idx < length(events) - 1, do: Enum.at(events, idx + 1), else: current
  end

  defp navigate_event("prev", events, current) do
    idx = Enum.find_index(events, &(&1.id == current.id))
    if idx && idx > 0, do: Enum.at(events, idx - 1), else: current
  end

  defp navigate_event(_, _events, current), do: current

  def handle_restore_state(params, socket) do
    socket
    |> maybe_restore(:view_mode, params["view_mode"])
    |> maybe_restore(:filter_source_app, params["filter_source_app"])
    |> maybe_restore(:filter_session_id, params["filter_session_id"])
    |> maybe_restore(:filter_event_type, params["filter_event_type"])
    |> maybe_restore(:search_feed, params["search_feed"])
    |> maybe_restore(:search_sessions, params["search_sessions"])
    |> maybe_restore(:selected_team, params["selected_team"])
    |> maybe_restore(:sidebar_collapsed, params["sidebar_collapsed"])
  end

  defp maybe_restore(socket, _key, nil), do: socket
  defp maybe_restore(socket, _key, ""), do: socket

  defp maybe_restore(socket, :view_mode, value) when is_binary(value) do
    DashboardViewRouter.assign_view(socket, value)
  end

  defp maybe_restore(socket, :sidebar_collapsed, "true"),
    do: Phoenix.Component.assign(socket, :sidebar_collapsed, true)

  defp maybe_restore(socket, :sidebar_collapsed, _), do: socket

  defp maybe_restore(socket, key, value), do: Phoenix.Component.assign(socket, key, value)

  defp find_agent_by_id(teams, agent_id) do
    teams
    |> Enum.flat_map(& &1.members)
    |> Enum.find(&(&1[:agent_id] == agent_id))
  end
end
