defmodule ObservatoryWeb.DashboardFilterHandlers do
  @moduledoc """
  Handlers for filtering, searching, and view selection events.
  """
  import Phoenix.Component, only: [assign: 3]
  import ObservatoryWeb.DashboardDataHelpers, only: [blank_to_nil: 1]
  import ObservatoryWeb.DashboardTeamHelpers, only: [derive_teams: 2, team_member_sids: 1]

  def handle_filter(params, socket) do
    socket
    |> assign(:filter_source_app, blank_to_nil(params["source_app"]))
    |> assign(:filter_session_id, blank_to_nil(params["session_id"]))
    |> assign(:filter_event_type, blank_to_nil(params["event_type"]))
  end

  def handle_clear_filters(socket) do
    socket
    |> assign(:filter_source_app, nil)
    |> assign(:filter_session_id, nil)
    |> assign(:filter_event_type, nil)
    |> assign(:search_feed, "")
    |> assign(:search_sessions, "")
  end

  def handle_search_feed(q, socket) do
    socket |> assign(:search_feed, q)
  end

  def handle_search_sessions(q, socket) do
    socket |> assign(:search_sessions, q)
  end

  def handle_filter_tool(tool, socket) do
    socket |> assign(:search_feed, tool)
  end

  def handle_filter_tool_use_id(tuid, socket) do
    socket |> assign(:search_feed, tuid)
  end

  def handle_filter_session(sid, socket) do
    socket |> assign(:filter_session_id, sid)
  end

  def handle_set_view(mode, socket) do
    socket
    |> assign(:view_mode, String.to_existing_atom(mode))
    |> Phoenix.LiveView.push_event("view_mode_changed", %{view_mode: mode})
  end

  def handle_filter_team(name, socket) do
    team =
      Enum.find(
        derive_teams(socket.assigns.events, socket.assigns.disk_teams),
        &(&1.name == name)
      )

    if team do
      sids = team_member_sids(team)

      case sids do
        [sid] -> socket |> assign(:filter_session_id, sid)
        _ -> socket |> assign(:search_feed, name)
      end
    else
      socket
    end
  end

  def handle_filter_agent(sid, socket) do
    socket |> assign(:filter_session_id, sid) |> assign(:view_mode, :feed)
  end

  def handle_apply_preset(preset, socket) do
    case preset do
      "failed_tools" ->
        socket
        |> assign(:filter_event_type, "PostToolUseFailure")
        |> assign(:filter_source_app, nil)
        |> assign(:filter_session_id, nil)
        |> assign(:search_feed, "")

      "team_events" ->
        socket
        |> assign(:filter_event_type, nil)
        |> assign(:filter_source_app, nil)
        |> assign(:filter_session_id, nil)
        |> assign(:search_feed, "SendMessage")

      "slow" ->
        socket
        |> assign(:filter_event_type, nil)
        |> assign(:filter_source_app, nil)
        |> assign(:filter_session_id, nil)
        |> assign(:search_feed, "")
        |> assign(:filter_slow, true)

      "errors_only" ->
        socket
        |> assign(:filter_event_type, "PostToolUseFailure")
        |> assign(:filter_source_app, nil)
        |> assign(:filter_session_id, nil)
        |> assign(:search_feed, "")

      _ ->
        socket
    end
  end
end
