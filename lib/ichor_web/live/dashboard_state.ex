defmodule IchorWeb.DashboardState do
  @moduledoc """
  Recomputes derived dashboard assigns using Ash domain resources.
  Two tiers: `recompute/1` (full data + view) and `recompute_view/1` (display-only, no queries).
  """

  import Phoenix.Component, only: [assign: 3]
  import IchorWeb.DashboardDataHelpers, only: [filtered_events: 1, filtered_sessions: 2]
  import IchorWeb.DashboardTeamHelpers, only: [all_team_sids: 1]
  import IchorWeb.DashboardFeedHelpers, only: [build_feed_groups: 2]

  alias Ichor.Activity
  alias Ichor.Dag.Status
  alias Ichor.Fleet
  alias Ichor.Fleet.Analysis.Queries, as: FQ
  alias Ichor.Fleet.Analysis.SessionEviction
  alias Ichor.Fleet.RuntimeView
  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.Gateway.HITLRelay
  alias Ichor.Gateway.TmuxDiscovery
  alias Ichor.Notes

  def default_assigns(disk_teams) do
    %{
      events: [],
      filter_source_app: nil,
      filter_session_id: nil,
      filter_event_type: nil,
      filter_slow: false,
      search_feed: "",
      search_sessions: "",
      search_history: [],
      selected_event: nil,
      selected_task: nil,
      selected_agent: nil,
      expanded_events: [],
      now: DateTime.utc_now(),
      page_title: "ICHOR IV",
      view_mode: :command,
      activity_tab: :comms,
      pipeline_tab: :dag,
      agent_slideout: nil,
      slideout_terminal: "",
      slideout_activity: [],
      expanded_sessions: MapSet.new(),
      disk_teams: disk_teams,
      dag_state: Status.state(),
      protocol_stats: %{},
      selected_dag_task: nil,
      selected_command_agent: nil,
      show_add_project: false,
      selected_team: nil,
      selected_message_target: nil,
      show_shortcuts_help: false,
      collapsed_fleet_teams: MapSet.new(),
      comms_team_filter: nil,
      comms_agent_filter: [],
      sidebar_collapsed: false,
      active_tmux_session: nil,
      tmux_output: "",
      tmux_sessions: [],
      tmux_panels: [],
      tmux_outputs: %{},
      tmux_layout: :tabs,
      agent_index: %{},
      paused_sessions: MapSet.new(),
      mailbox_messages: [],
      # Workshop team builder
      ws_agents: [],
      ws_spawn_links: [],
      ws_comm_rules: [],
      ws_selected_agent: nil,
      ws_next_id: 1,
      ws_team_name: "alpha",
      ws_strategy: "one_for_one",
      ws_default_model: "sonnet",
      ws_cwd: "",
      ws_blueprint_id: nil,
      ws_blueprints: [],
      ws_agent_types: [],
      ws_editing_type: nil,
      # Toast notifications
      toasts: [],
      # Archon overlay
      show_archon: false,
      archon_tab: :command,
      archon_messages: [],
      archon_history: [],
      archon_loading: false,
      archon_snapshot: %{},
      archon_attention: [],
      # Recompute-derived assigns (defaults for static render before :load_data)
      teams: [],
      has_teams: false,
      sessions: [],
      total_sessions: 0,
      messages: [],
      active_tasks: [],
      errors: [],
      error_groups: [],
      visible_events: [],
      event_notes: [],
      feed_groups: [],
      sel_team: nil,
      nav_view: :pipeline,
      # Stream view
      stream_filter: "",
      stream_paused: false,
      # MES
      mes_projects: [],
      mes_scheduler_status: %{tick: 0, active_runs: 0, next_tick_in: 60_000, paused: false},
      genesis_node: nil,
      gate_report: nil,
      genesis_sub_tab: :decisions,
      genesis_selected: nil,
      selected_mes_project: nil
    }
  end

  @doc "Full recompute: queries all Ash domains + derives view assigns."
  def recompute(socket) do
    do_recompute(socket)
  rescue
    ArgumentError -> socket
  end

  defp do_recompute(socket) do
    assigns = socket.assigns

    # Evict events from stale sessions (no activity in TTL)
    events = SessionEviction.evict_stale(assigns.events, assigns.now)
    socket = assign(socket, :events, events)
    assigns = socket.assigns

    # Ash domain queries
    teams = Fleet.list_alive_teams()
    all_teams = Fleet.list_teams()
    agents = Fleet.list_agents()
    messages = Activity.list_recent_messages()
    event_tasks = Activity.list_current_tasks() |> Enum.map(&task_to_map/1)
    errors = Activity.list_recent_errors()
    error_groups = Activity.list_error_groups()

    # Session derivation (Fleet.Queries)
    all_sessions =
      FQ.active_sessions(assigns.events, tmux: assigns[:tmux_sessions] || [], now: assigns.now)

    tmux_only = FQ.active_sessions([], tmux: assigns[:tmux_sessions] || [], now: assigns.now)
    team_sids = all_team_sids(all_teams)

    standalone =
      all_sessions
      |> Enum.reject(fn s ->
        MapSet.member?(team_sids, s.session_id) or infrastructure_entry?(s)
      end)

    event_notes = Notes.list_notes()

    # Auto-select team when only 1 exists
    selected_team = RuntimeView.resolve_selected_team(assigns.selected_team, teams)
    sel_team = RuntimeView.find_team(teams, selected_team)

    active_tasks =
      cond do
        sel_team && sel_team.tasks != [] -> sel_team.tasks
        event_tasks != [] -> event_tasks
        true -> []
      end

    # Tmux session list (for sidebar)
    tmux_session_names = safe_tmux_sessions()
    teams = RuntimeView.merge_display_teams(teams, agents, tmux_session_names)

    # Unified agent index from Fleet.Agent
    agent_index = RuntimeView.build_agent_lookup(agents)

    # Template-layer data
    paused_sessions = safe_paused_sessions()
    operator_messages = Ichor.MessageRouter.recent_messages(50)
    hook_messages = load_messages(messages, 50)

    mailbox_messages =
      (operator_messages ++ hook_messages)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
      |> Enum.take(50)

    # Conditional: only compute expensive derivations for active view
    feed_groups = maybe_feed(assigns, teams, tmux_only)

    socket
    |> assign(:agent_index, agent_index)
    |> assign(:visible_events, filtered_events(assigns))
    |> assign(:feed_groups, feed_groups)
    |> assign(:sessions, filtered_sessions(standalone, assigns.search_sessions))
    |> assign(:total_sessions, length(all_sessions))
    |> assign(:teams, teams)
    |> assign(:has_teams, teams != [])
    |> assign(:active_tasks, active_tasks)
    |> assign(:messages, messages)
    |> assign(:event_notes, event_notes)
    |> assign(:selected_team, selected_team)
    |> assign(:sel_team, sel_team)
    |> assign(:errors, errors)
    |> assign(:error_groups, error_groups)
    |> assign(:paused_sessions, paused_sessions)
    |> assign(:mailbox_messages, mailbox_messages)
    |> assign(:tmux_sessions, tmux_session_names)
  end

  @doc "View-only recompute: re-derives display assigns from existing data. No Ash/SQL queries."
  def recompute_view(socket) do
    assigns = socket.assigns
    teams = assigns[:teams] || []

    selected_team = RuntimeView.resolve_selected_team(assigns.selected_team, teams)
    sel_team = RuntimeView.find_team(teams, selected_team)

    active_tasks =
      cond do
        sel_team && sel_team.tasks != [] -> sel_team.tasks
        (assigns[:active_tasks] || []) != [] -> assigns.active_tasks
        true -> []
      end

    socket
    |> assign(:visible_events, filtered_events(assigns))
    |> assign(:selected_team, selected_team)
    |> assign(:sel_team, sel_team)
    |> assign(:active_tasks, active_tasks)
  end

  defp safe_paused_sessions do
    HITLRelay.paused_sessions() |> MapSet.new()
  rescue
    _ -> MapSet.new()
  end

  defp safe_tmux_sessions do
    Tmux.list_sessions()
  rescue
    _ -> []
  end

  # Reuse already-fetched messages instead of querying Activity.Message.recent!() again
  defp load_messages(messages, limit) do
    messages
    |> Enum.take(limit)
    |> Enum.map(fn m ->
      %{
        id: m.id,
        from: m.sender_session,
        to: m.recipient,
        content: m.content,
        type: m.type,
        read: false,
        timestamp: m.timestamp
      }
    end)
  end

  # Feed groups needed on command/activity views with feed/comms tab
  defp maybe_feed(assigns, teams, tmux_only) do
    if assigns.view_mode == :command and assigns.activity_tab in [:feed, :comms] do
      groups = build_feed_groups(assigns.events, teams)
      groups ++ Enum.map(tmux_only, &tmux_feed_entry(&1, assigns.now))
    else
      assigns[:feed_groups] || []
    end
  end

  defp infrastructure_entry?(%{session_id: sid}) do
    sid == "operator" or TmuxDiscovery.infrastructure_session?(sid)
  end

  defp task_to_map(%{id: _id} = t), do: Map.from_struct(t)
  defp task_to_map(t) when is_map(t), do: t

  defp tmux_feed_entry(s, now) do
    %{
      session_id: s.session_id,
      agent_name: s[:tmux_session] || s.source_app,
      role: :standalone,
      events: [],
      turns: [],
      turn_count: 0,
      session_start: nil,
      session_end: nil,
      stop_event: nil,
      model: nil,
      cwd: nil,
      permission_mode: nil,
      source_app: s.source_app,
      event_count: 0,
      tool_count: 0,
      subagent_count: 0,
      total_duration_ms: nil,
      start_time: now,
      end_time: nil,
      is_active: true
    }
  end
end
