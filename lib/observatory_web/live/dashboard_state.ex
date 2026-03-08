defmodule ObservatoryWeb.DashboardState do
  @moduledoc """
  Recomputes derived dashboard assigns using Ash domain resources.
  Replaces the monolithic `prepare_assigns/1` with Ash-backed data queries.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  import ObservatoryWeb.DashboardDataHelpers, only: [filtered_events: 1, filtered_sessions: 2, compute_tool_analytics: 1]
  import ObservatoryWeb.DashboardMessageHelpers, only: [search_messages: 2, group_messages_by_thread: 1]
  import ObservatoryWeb.DashboardTeamHelpers, only: [team_member_sids: 1, all_team_sids: 1]
  import ObservatoryWeb.DashboardFeedHelpers, only: [build_feed_groups: 2]
  import ObservatoryWeb.DashboardTimelineHelpers, only: [compute_timeline_data: 1]
  import ObservatoryWeb.DashboardSessionHelpers, only: [short_model_name: 1]
  import ObservatoryWeb.DashboardFormatHelpers, only: [session_duration_sec: 1]

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

    # Session derivation (still needed for feed, topology, filtering)
    all_sessions = active_sessions_from_events(assigns.events, assigns)
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

    # Analytics
    analytics = compute_tool_analytics(assigns.events)
    timeline = compute_timeline_data(assigns.events)

    # Feed
    feed_groups = build_feed_groups(assigns.events, teams)
    tmux_only = build_tmux_only(assigns, all_sessions)
    feed_groups = feed_groups ++ Enum.map(tmux_only, &tmux_feed_entry(&1, assigns.now))

    # Inspector
    inspected_names = Enum.map(assigns.inspected_teams, & &1.name)
    refreshed_inspected = Enum.filter(teams, fn t -> t.name in inspected_names end)

    inspector_events = compute_inspector_events(refreshed_inspected, assigns.events)

    # Topology
    {topo_nodes, topo_edges} = compute_topology(all_sessions, teams, assigns)

    # Costs (load from SQLite, lightweight aggregation)
    cost_data = Observatory.Costs.CostAggregator.load_cost_data()

    # Unified agent index: registry (authoritative) merged with event-derived data
    # Maps ALL known identifiers (id, session_id, short_name) to the same agent record
    registry_agents = Observatory.Gateway.AgentRegistry.list_all()
    agent_index = build_agent_index(registry_agents, assigns.events, assigns.now)

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
    |> push_event("fleet_topology_update", %{nodes: topo_nodes, edges: topo_edges})
  end

  # ── Unified Agent Index ──────────────────────────────────────────────
  #
  # Builds a map keyed by ALL known identifiers for each agent.
  # Registry is authoritative for status, cwd, team, role.
  # Events provide live data: current_tool, recent_activity, event_count.
  #
  # Keys per agent: id, session_id, short_name (all pointing to the same map)
  defp build_agent_index(registry_agents, events, now) do
    # Event data grouped by session_id
    event_data =
      events
      |> Enum.group_by(& &1.session_id)
      |> Map.new(fn {sid, evts} -> {sid, summarize_events(evts, now)} end)

    # Build entries from registry agents, enriched with event data
    registry_agents
    |> Enum.flat_map(fn reg ->
      ev = Map.get(event_data, reg.session_id, %{})

      agent = %{
        agent_id: reg.id,
        session_id: reg.session_id,
        short_name: reg.short_name,
        name: reg.short_name || reg.id,
        status: reg.status || :idle,
        role: reg.role,
        team: reg.team,
        model: reg.model,
        cwd: reg.cwd,
        project: if(reg.cwd, do: Path.basename(reg.cwd), else: nil),
        source_app: ev[:source_app],
        host: Map.get(reg, :host, "local"),
        channels: reg.channels,
        tmux_session: get_in(reg, [:channels, :tmux]),
        current_tool: ev[:current_tool],
        event_count: ev[:event_count] || 0,
        tool_count: ev[:tool_count] || 0,
        recent_activity: ev[:recent_activity] || [],
        last_event_at: reg.last_event_at
      }

      # Map all known keys to the same agent record
      keys = Enum.uniq([reg.id, reg.session_id, reg.short_name]) |> Enum.reject(&is_nil/1)
      Enum.map(keys, fn k -> {k, agent} end)
    end)
    |> Observatory.Gateway.AgentRegistry.dedup_by_status()
  end

  defp summarize_events(events, now) do
    sorted = Enum.sort_by(events, & &1.inserted_at, {:desc, DateTime})

    %{
      event_count: length(events),
      tool_count: Enum.count(events, &(&1.hook_event_type == :PreToolUse)),
      current_tool: find_current_tool(sorted, now),
      recent_activity: build_recent_activity(sorted, now),
      source_app: Enum.find_value(events, & &1.source_app)
    }
  end

  defp find_current_tool(sorted_events, now) do
    post_ids =
      sorted_events
      |> Enum.filter(&(&1.hook_event_type in [:PostToolUse, :PostToolUseFailure]))
      |> MapSet.new(& &1.tool_use_id)

    sorted_events
    |> Enum.filter(&(&1.hook_event_type == :PreToolUse))
    |> Enum.find(fn e -> e.tool_use_id && not MapSet.member?(post_ids, e.tool_use_id) end)
    |> case do
      nil -> nil
      pre -> %{tool_name: pre.tool_name, elapsed: div(DateTime.diff(now, pre.inserted_at, :millisecond), 1000)}
    end
  end

  defp build_recent_activity(sorted_events, now) do
    sorted_events
    |> Enum.take(20)
    |> Enum.flat_map(&event_to_activity(&1, now))
    |> Enum.take(5)
  end

  defp event_to_activity(e, now) do
    age = DateTime.diff(now, e.inserted_at, :second)
    age_str = format_age(age)

    case e.hook_event_type do
      :PreToolUse ->
        tool = e.tool_name || "?"
        [%{type: :tool, tool: tool, detail: "", age: age_str}]

      :PostToolUseFailure ->
        tool = e.tool_name || "?"
        [%{type: :error, tool: tool, detail: "failed", age: age_str}]

      :Notification ->
        text = (e.payload || %{})["message"] || (e.payload || %{})["content"] || e.summary || ""
        if text != "", do: [%{type: :notify, detail: String.slice(text, 0, 120), age: age_str}], else: []

      :TaskCompleted ->
        task_id = (e.payload || %{})["task_id"] || "?"
        [%{type: :task_done, detail: "Task #{task_id} completed", age: age_str}]

      _ ->
        []
    end
  end

  defp format_age(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_age(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m"
  defp format_age(seconds), do: "#{div(seconds, 3600)}h"

  # Session derivation from raw events (still needed for feed groups, topology)
  defp active_sessions_from_events(events, assigns) do
    sessions =
      events
      |> Enum.group_by(&{&1.source_app, &1.session_id})
      |> Enum.map(fn {{app, sid}, evts} ->
        sorted = Enum.sort_by(evts, & &1.inserted_at, {:desc, DateTime})
        latest = hd(sorted)
        ended? = Enum.any?(evts, &(&1.hook_event_type == :SessionEnd))

        %{
          source_app: app,
          session_id: sid,
          event_count: length(evts),
          latest_event: latest,
          first_event: List.last(sorted),
          ended?: ended?,
          model: find_model(evts),
          permission_mode: latest.permission_mode,
          cwd: latest.cwd || find_cwd(evts)
        }
      end)
      |> Enum.sort_by(& &1.latest_event.inserted_at, {:desc, DateTime})

    # Append tmux-only sessions
    sessions ++ build_tmux_only(assigns, sessions)
  end

  defp build_tmux_only(assigns, _existing_sessions) do
    known_tmux =
      assigns.events
      |> Enum.map(& &1.tmux_session)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    (assigns[:tmux_sessions] || [])
    |> Enum.reject(fn name -> MapSet.member?(known_tmux, name) end)
    |> Enum.map(fn name ->
      now = assigns.now

      %{
        source_app: name,
        session_id: name,
        event_count: 0,
        latest_event: %{inserted_at: now},
        first_event: %{inserted_at: now},
        ended?: false,
        model: nil,
        permission_mode: nil,
        cwd: nil,
        tmux_session: name
      }
    end)
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

  defp compute_inspector_events(inspected_teams, events) do
    sids =
      inspected_teams
      |> Enum.flat_map(&team_member_sids/1)
      |> MapSet.new()

    if MapSet.size(sids) > 0 do
      events
      |> Enum.filter(fn e -> MapSet.member?(sids, e.session_id) end)
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Enum.take(200)
    else
      []
    end
  end

  defp compute_topology(all_sessions, teams, assigns) do
    team_member_index =
      teams
      |> Enum.flat_map(fn t ->
        Enum.map(t.members, fn m ->
          {m[:agent_id], %{team: t.name, role: m[:name] || m[:agent_type]}}
        end)
      end)
      |> Map.new()

    session_sids = MapSet.new(all_sessions, & &1.session_id)

    session_nodes =
      Enum.map(all_sessions, fn s ->
        status =
          cond do
            s.ended? -> "dead"
            DateTime.diff(assigns.now, s.latest_event.inserted_at, :second) > 120 -> "idle"
            true -> "active"
          end

        team_info = Map.get(team_member_index, s.session_id, %{})
        dur = DateTime.diff(assigns.now, s.first_event.inserted_at, :second)

        %{
          trace_id: s.session_id,
          agent_id: s.session_id,
          state: status,
          label: team_info[:role] || s.source_app || String.slice(s.session_id, 0, 8),
          model: short_model_name(s.model),
          team: team_info[:team],
          events: s.event_count,
          cwd: if(s.cwd, do: Path.basename(s.cwd), else: nil),
          duration: session_duration_sec(dur)
        }
      end)

    member_nodes =
      teams
      |> Enum.flat_map(fn team ->
        team.members
        |> Enum.filter(fn m -> m[:agent_id] && not MapSet.member?(session_sids, m[:agent_id]) end)
        |> Enum.map(fn m ->
          %{
            trace_id: m[:agent_id],
            agent_id: m[:agent_id],
            state: to_string(m[:status] || :idle),
            label: m[:name] || m[:agent_type] || String.slice(m[:agent_id] || "", 0, 8),
            model: short_model_name(m[:model]),
            team: team.name,
            events: m[:event_count] || 0,
            cwd: if(m[:cwd], do: Path.basename(m[:cwd]), else: nil),
            duration: nil
          }
        end)
      end)

    topo_nodes = session_nodes ++ member_nodes

    topo_edges =
      teams
      |> Enum.flat_map(fn team ->
        sids = Enum.map(team.members, & &1[:agent_id]) |> Enum.reject(&is_nil/1)

        sids
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [from, to] ->
          %{from: from, to: to, traffic_volume: 0, latency_ms: 0, status: "active"}
        end)
      end)

    {topo_nodes, topo_edges}
  end

  defp find_model(events),
    do: Enum.find_value(events, fn e -> e.payload["model"] || e.model_name end)

  defp find_cwd(events), do: Enum.find_value(events, fn e -> e.cwd end)
end
