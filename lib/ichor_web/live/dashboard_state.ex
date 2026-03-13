defmodule IchorWeb.DashboardState do
  @moduledoc """
  Recomputes derived dashboard assigns using Ash domain resources.
  Two tiers: `recompute/1` (full data + view) and `recompute_view/1` (display-only, no queries).
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  import IchorWeb.DashboardDataHelpers, only: [filtered_events: 1, filtered_sessions: 2]
  import IchorWeb.DashboardMessageHelpers, only: [search_messages: 2, group_messages_by_thread: 1]
  import IchorWeb.DashboardTeamHelpers, only: [all_team_sids: 1]
  import IchorWeb.DashboardFeedHelpers, only: [build_feed_groups: 2]

  alias Ichor.Activity.Error
  alias Ichor.Activity.EventAnalysis
  alias Ichor.Activity.Message
  alias Ichor.Activity.Task
  alias Ichor.Costs.CostAggregator
  alias Ichor.Fleet.Agent
  alias Ichor.Fleet.Queries, as: FQ
  alias Ichor.Fleet.Team
  alias Ichor.Gateway.AgentRegistry
  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.Gateway.HITLRelay
  alias Ichor.Gateway.TmuxDiscovery
  alias Ichor.Notes
  alias Ichor.SwarmMonitor

  def default_assigns(disk_teams) do
    %{
      events: [],
      filter_source_app: nil,
      filter_session_id: nil,
      filter_event_type: nil,
      filter_slow: false,
      search_feed: "",
      search_sessions: "",
      search_messages: "",
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
      forensic_tab: :archive,
      control_tab: :emergency,
      agent_slideout: nil,
      slideout_terminal: "",
      slideout_activity: [],
      expanded_sessions: MapSet.new(),
      disk_teams: disk_teams,
      swarm_state: SwarmMonitor.get_state(),
      protocol_stats: %{},
      selected_dag_task: nil,
      selected_command_agent: nil,
      selected_command_task: nil,
      show_add_project: false,
      selected_team: nil,
      mailbox_counts: %{},
      collapsed_threads: %{},
      show_shortcuts_help: false,
      show_create_task_modal: false,
      inspected_teams: [],
      inspector_layout: :horizontal,
      inspector_maximized: false,
      inspector_size: :default,
      output_mode: :all_live,
      agent_toggles: %{},
      selected_message_target: nil,
      inspector_events: [],
      current_session_id: "operator",
      collapsed_fleet_teams: MapSet.new(),
      comms_team_filter: nil,
      comms_agent_filter: [],
      dirty: true,
      sidebar_collapsed: false,
      active_tmux_session: nil,
      tmux_output: "",
      tmux_sessions: [],
      tmux_panels: [],
      tmux_outputs: %{},
      tmux_layout: :tabs,
      # Phase 5 - Fleet Command
      throughput_rate: nil,
      cost_heatmap: [],
      node_status: nil,
      latency_metrics: %{},
      mtls_status: "Not configured",
      agent_grid_open: false,
      selected_topology_node: nil,
      # Phase 5 - Session Cluster & Registry
      entropy_filter_active: false,
      entropy_threshold: 0.7,
      selected_session_id: nil,
      scratchpad_intents: [],
      feed_panel_open: false,
      messages_panel_open: false,
      tasks_panel_open: false,
      protocols_panel_open: false,
      agent_types: [],
      route_weights: %{},
      capability_sort_field: :agent_type,
      capability_sort_dir: :asc,
      route_weight_errors: %{},
      # Phase 5 - God Mode
      kill_switch_confirm_step: nil,
      agent_classes: [],
      instructions_confirm_pending: nil,
      instructions_banner: nil,
      # Phase 5 - Scheduler
      cron_jobs: [],
      dlq_entries: [],
      zombie_agents: [],
      # Phase 5 - Forensic
      archive_search: "",
      archive_results: [],
      cost_group_by: :agent_id,
      cost_attribution: [],
      webhook_logs: [],
      policy_rules: [],
      forensic_audit_open: false,
      forensic_topology_open: false,
      forensic_entropy_open: false,
      expanded_protocol_items: MapSet.new(),
      cost_data: %{by_model: [], by_session: [], totals: %{}},
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
      # Recompute-derived assigns (defaults for static render before :load_data)
      teams: [],
      has_teams: false,
      sessions: [],
      total_sessions: 0,
      messages: [],
      message_threads: [],
      active_tasks: [],
      errors: [],
      error_groups: [],
      analytics: %{},
      timeline: [],
      visible_events: [],
      event_notes: [],
      feed_groups: [],
      sel_team: nil,
      nav_view: :pipeline,
      # Stream view
      stream_events: [],
      stream_filter: "",
      stream_paused: false,
      # MES
      mes_projects: [],
      mes_scheduler_status: %{tick: 0, active_runs: 0, next_tick_in: 60_000}
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

    # Ash domain queries
    teams = Team.alive!()
    all_teams = Team.all!()
    messages = Message.recent!()
    event_tasks = Task.current!() |> Enum.map(&task_to_map/1)
    errors = Error.recent!()
    error_groups = Error.by_tool!()

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

    # Messages (single query, reused for both assigns)
    filtered_messages = search_messages(messages, assigns.search_messages)
    message_threads = group_messages_by_thread(filtered_messages)

    event_notes = Notes.list_notes()

    # Auto-select team when only 1 exists
    selected_team = resolve_selected_team(assigns.selected_team, teams)
    sel_team = Enum.find(teams, fn t -> t.name == selected_team end)

    active_tasks =
      cond do
        sel_team && sel_team.tasks != [] -> sel_team.tasks
        event_tasks != [] -> event_tasks
        true -> []
      end

    # Inspector (Fleet.Queries) -- skip if no teams inspected
    inspected_names = Enum.map(assigns.inspected_teams, & &1.name)
    refreshed_inspected = Enum.filter(teams, fn t -> t.name in inspected_names end)

    inspector_events =
      if refreshed_inspected != [],
        do: FQ.inspector_events(refreshed_inspected, assigns.events),
        else: []

    # Topology (Fleet.Queries)
    {topo_nodes, topo_edges} = FQ.topology(all_sessions, teams, assigns.now)

    # Unified agent index from Fleet.Agent
    agent_index = build_agent_lookup(Agent.all!())

    # Tmux session list (for sidebar)
    tmux_session_names = safe_tmux_sessions()

    # Template-layer data
    paused_sessions = safe_paused_sessions()
    mailbox_messages = load_messages(messages, 50)

    # Conditional: only compute expensive derivations for active view
    {analytics, timeline} = maybe_analytics(assigns)
    feed_groups = maybe_feed(assigns, teams, tmux_only)
    cost_data = maybe_costs(assigns)

    socket
    |> assign(:agent_index, agent_index)
    |> assign(:visible_events, filtered_events(assigns))
    |> assign(:cost_data, cost_data)
    |> assign(:feed_groups, feed_groups)
    |> assign(:inspected_teams, refreshed_inspected)
    |> assign(:inspector_events, inspector_events)
    |> assign(:sessions, filtered_sessions(standalone, assigns.search_sessions))
    |> assign(:total_sessions, length(all_sessions))
    |> assign(:teams, teams)
    |> assign(:has_teams, teams != [])
    |> assign(:active_tasks, active_tasks)
    |> assign(:messages, messages)
    |> assign(:message_threads, message_threads)
    |> assign(:event_notes, event_notes)
    |> assign(:selected_team, selected_team)
    |> assign(:sel_team, sel_team)
    |> assign(:errors, errors)
    |> assign(:error_groups, error_groups)
    |> assign(:analytics, analytics)
    |> assign(:timeline, timeline)
    |> assign(:paused_sessions, paused_sessions)
    |> assign(:mailbox_messages, mailbox_messages)
    |> assign(:tmux_sessions, tmux_session_names)
    |> push_event("fleet_topology_update", %{nodes: topo_nodes, edges: topo_edges})
  end

  @doc "View-only recompute: re-derives display assigns from existing data. No Ash/SQL queries."
  def recompute_view(socket) do
    assigns = socket.assigns
    teams = assigns[:teams] || []

    selected_team = resolve_selected_team(assigns.selected_team, teams)
    sel_team = Enum.find(teams, fn t -> t.name == selected_team end)

    active_tasks =
      cond do
        sel_team && sel_team.tasks != [] -> sel_team.tasks
        (assigns[:active_tasks] || []) != [] -> assigns.active_tasks
        true -> []
      end

    filtered_messages = search_messages(assigns[:messages] || [], assigns.search_messages)
    message_threads = group_messages_by_thread(filtered_messages)

    socket
    |> assign(:visible_events, filtered_events(assigns))
    |> assign(:message_threads, message_threads)
    |> assign(:selected_team, selected_team)
    |> assign(:sel_team, sel_team)
    |> assign(:active_tasks, active_tasks)
  end

  defp resolve_selected_team(current, teams) do
    cond do
      current -> current
      length(teams) == 1 -> hd(teams).name
      true -> nil
    end
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

  defp build_agent_lookup(agents) do
    agents
    |> Enum.flat_map(fn a ->
      agent_map = Map.from_struct(a)

      agent_map =
        Map.merge(agent_map, %{
          team: a.team_name,
          project: if(a.cwd, do: Path.basename(a.cwd), else: nil),
          tmux_session: get_in(a.channels || %{}, [:tmux]) || a.tmux_session
        })

      [a.agent_id, a.session_id, a.short_name]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(&{&1, agent_map})
    end)
    |> AgentRegistry.dedup_by_status()
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

  # Analytics + timeline only needed when activity analytics/timeline tab is active
  defp maybe_analytics(assigns) do
    if assigns.view_mode == :activity and assigns.activity_tab in [:analytics, :timeline] do
      {EventAnalysis.tool_analytics(assigns.events), EventAnalysis.timeline(assigns.events)}
    else
      {assigns[:analytics] || %{}, assigns[:timeline] || []}
    end
  end

  # Feed groups needed on command/activity views with feed/comms tab
  defp maybe_feed(assigns, teams, tmux_only) do
    if assigns.view_mode in [:command, :activity] and assigns.activity_tab in [:feed, :comms] do
      groups = build_feed_groups(assigns.events, teams)
      groups ++ Enum.map(tmux_only, &tmux_feed_entry(&1, assigns.now))
    else
      assigns[:feed_groups] || []
    end
  end

  # Cost data only needed on forensic/control views (3 SQL queries)
  defp maybe_costs(assigns) do
    if assigns.view_mode in [:forensic, :control] do
      CostAggregator.load_cost_data()
    else
      assigns[:cost_data] || %{by_model: [], by_session: [], totals: %{}}
    end
  end

  defp infrastructure_entry?(%{session_id: sid}) do
    sid == "operator" or TmuxDiscovery.infrastructure_session?(sid)
  end

  defp task_to_map(%Ichor.Activity.Task{} = t), do: Map.from_struct(t)
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
