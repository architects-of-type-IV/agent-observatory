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
    # Find this session's agent info from teams
    agent =
      socket.assigns.teams
      |> Enum.flat_map(& &1.members)
      |> Enum.find(fn m -> m[:agent_id] == sid || m[:session_id] == sid end)

    agent_info =
      agent ||
        %{
          agent_id: sid,
          name: String.slice(sid, 0, 8),
          status: :unknown,
          health: :unknown,
          health_issues: []
        }

    socket
    |> assign(:filter_session_id, sid)
    |> assign(:selected_command_agent, agent_info)
    |> Phoenix.LiveView.push_event("highlight_node", %{session_id: sid})
  end

  def handle_set_view(mode, socket) do
    {view_mode, sub_tab_assigns} = normalize_view_mode(mode)

    socket
    |> assign(:view_mode, view_mode)
    |> then(fn s -> Enum.reduce(sub_tab_assigns, s, fn {k, v}, acc -> assign(acc, k, v) end) end)
    |> Phoenix.LiveView.push_event("view_mode_changed", %{view_mode: Atom.to_string(view_mode)})
  end

  # Map legacy view modes to new consolidated screens + sub-tabs
  defp normalize_view_mode(mode) when is_binary(mode) do
    case mode do
      # Primary screens
      "command" -> {:command, []}
      "activity" -> {:activity, []}
      "pipeline" -> {:pipeline, []}
      "forensic" -> {:forensic, []}
      "control" -> {:control, []}
      # Legacy -> Command
      "fleet_command" -> {:command, []}
      "overview" -> {:command, []}
      "agents" -> {:command, []}
      "teams" -> {:command, []}
      "protocols" -> {:command, []}
      # Legacy -> Activity (with sub-tab)
      "feed" -> {:activity, [{:activity_tab, :feed}]}
      "timeline" -> {:activity, [{:activity_tab, :timeline}]}
      "analytics" -> {:activity, [{:activity_tab, :analytics}]}
      "messages" -> {:activity, [{:activity_tab, :messages}]}
      "errors" -> {:activity, [{:activity_tab, :errors}]}
      # Legacy -> Pipeline
      "tasks" -> {:pipeline, [{:pipeline_tab, :board}]}
      "scheduler" -> {:pipeline, [{:pipeline_tab, :scheduler}]}
      # Legacy -> Forensic
      "registry" -> {:forensic, [{:forensic_tab, :registry}]}
      # Legacy -> Control
      "god_mode" -> {:control, [{:control_tab, :emergency}]}
      "session_cluster" -> {:control, [{:control_tab, :sessions}]}
      # Fallback
      other ->
        try do
          {String.to_existing_atom(other), []}
        rescue
          ArgumentError -> {:command, []}
        end
    end
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
    socket |> assign(:filter_session_id, sid) |> assign(:view_mode, :activity) |> assign(:activity_tab, :feed)
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
