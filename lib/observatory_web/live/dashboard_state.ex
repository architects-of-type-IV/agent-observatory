defmodule ObservatoryWeb.DashboardState do
  @moduledoc """
  Recomputes derived dashboard assigns using Ash domain resources.
  Replaces the monolithic `prepare_assigns/1` with Ash-backed data queries.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  import ObservatoryWeb.DashboardDataHelpers, only: [filtered_events: 1, filtered_sessions: 2]
  import ObservatoryWeb.DashboardMessageHelpers, only: [search_messages: 2, group_messages_by_thread: 1]
  import ObservatoryWeb.DashboardTeamHelpers, only: [all_team_sids: 1]
  import ObservatoryWeb.DashboardFeedHelpers, only: [build_feed_groups: 2]

  alias Observatory.Activity.EventAnalysis
  alias Observatory.Fleet.Queries, as: FQ

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
      page_title: "Observatory",
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
      swarm_state: Observatory.SwarmMonitor.get_state(),
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
      ws_blueprints: []
    }
  end

  def recompute(socket) do
    assigns = socket.assigns

    # Ash domain queries replace scattered helper calls
    teams = Observatory.Fleet.Team.alive!()
    all_teams = Observatory.Fleet.Team.all!()
    messages = Observatory.Activity.Message.recent!()
    event_tasks = Observatory.Activity.Task.current!()
    errors = Observatory.Activity.Error.recent!()
    error_groups = Observatory.Activity.Error.by_tool!()

    # Session derivation (Fleet.Queries)
    all_sessions = FQ.active_sessions(assigns.events, tmux: assigns[:tmux_sessions] || [], now: assigns.now)
    tmux_only = FQ.active_sessions([], tmux: assigns[:tmux_sessions] || [], now: assigns.now)
    team_sids = all_team_sids(all_teams)
    standalone = Enum.reject(all_sessions, fn s -> MapSet.member?(team_sids, s.session_id) end)

    # Messages
    filtered_messages = search_messages(messages, assigns.search_messages)
    message_threads = group_messages_by_thread(filtered_messages)

    event_notes = Observatory.Notes.list_notes()

    # Auto-select team when only 1 exists
    selected_team =
      cond do
        assigns.selected_team -> assigns.selected_team
        length(teams) == 1 -> hd(teams).name
        true -> nil
      end

    sel_team = Enum.find(teams, fn t -> t.name == selected_team end)

    active_tasks =
      cond do
        sel_team && sel_team.tasks != [] -> sel_team.tasks
        event_tasks != [] -> event_tasks
        true -> []
      end

    # Analytics (Activity.EventAnalysis)
    analytics = EventAnalysis.tool_analytics(assigns.events)
    timeline = EventAnalysis.timeline(assigns.events)

    # Feed
    feed_groups = build_feed_groups(assigns.events, teams)
    feed_groups = feed_groups ++ Enum.map(tmux_only, &tmux_feed_entry(&1, assigns.now))

    # Inspector (Fleet.Queries)
    inspected_names = Enum.map(assigns.inspected_teams, & &1.name)
    refreshed_inspected = Enum.filter(teams, fn t -> t.name in inspected_names end)
    inspector_events = FQ.inspector_events(refreshed_inspected, assigns.events)

    # Topology (Fleet.Queries)
    {topo_nodes, topo_edges} = FQ.topology(all_sessions, teams, assigns.now)

    # Costs (load from SQLite, lightweight aggregation)
    cost_data = Observatory.Costs.CostAggregator.load_cost_data()

    # Unified agent index from Fleet.Agent (LoadAgents merges events + registry + BEAM)
    agent_index = build_agent_lookup(Observatory.Fleet.Agent.all!())

    # Template-layer data (moved out of heex preprocessing)
    paused_sessions = safe_paused_sessions()
    mailbox_messages = Observatory.Mailbox.all_messages(50)

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
    |> push_event("fleet_topology_update", %{nodes: topo_nodes, edges: topo_edges})
  end

  defp safe_paused_sessions do
    Observatory.Gateway.HITLRelay.paused_sessions() |> MapSet.new()
  rescue
    _ -> MapSet.new()
  end

  # Build multi-key lookup from Fleet.Agent structs (agent_id, session_id, short_name -> map)
  defp build_agent_lookup(agents) do
    agents
    |> Enum.flat_map(fn a ->
      agent_map = Map.from_struct(a)
      # Add computed fields expected by templates
      agent_map = Map.merge(agent_map, %{
        team: a.team_name,
        project: if(a.cwd, do: Path.basename(a.cwd), else: nil),
        tmux_session: get_in(a.channels || %{}, [:tmux]) || a.tmux_session
      })

      [a.agent_id, a.session_id, a.short_name]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(&{&1, agent_map})
    end)
    |> Observatory.Gateway.AgentRegistry.dedup_by_status()
  end

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
