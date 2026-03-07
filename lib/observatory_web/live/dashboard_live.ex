defmodule ObservatoryWeb.DashboardLive do
  use ObservatoryWeb, :live_view
  import ObservatoryWeb.DashboardTeamHelpers
  import ObservatoryWeb.DashboardDataHelpers
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.DashboardMessagingHandlers
  import ObservatoryWeb.DashboardTaskHandlers
  import ObservatoryWeb.DashboardSessionHelpers
  import ObservatoryWeb.DashboardUIHandlers
  import ObservatoryWeb.DashboardNotificationHandlers
  import ObservatoryWeb.DashboardFilterHandlers
  import ObservatoryWeb.DashboardNotesHandlers
  import ObservatoryWeb.DashboardAgentHelpers
  import ObservatoryWeb.DashboardAgentActivityHelpers
  import ObservatoryWeb.DashboardTeamInspectorHandlers
  import ObservatoryWeb.DashboardSwarmHandlers
  import ObservatoryWeb.DashboardGatewayHandlers
  import ObservatoryWeb.DashboardState, only: [recompute: 1]

  @max_events 500

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "events:stream")
      Phoenix.PubSub.subscribe(Observatory.PubSub, "teams:update")
      Phoenix.PubSub.subscribe(Observatory.PubSub, "agent:crashes")
      Phoenix.PubSub.subscribe(Observatory.PubSub, "agent:operator")
      Phoenix.PubSub.subscribe(Observatory.PubSub, "swarm:update")
      Phoenix.PubSub.subscribe(Observatory.PubSub, "protocols:update")
      Phoenix.PubSub.subscribe(Observatory.PubSub, "heartbeat")
      subscribe_gateway_topics()
      :ok
    end

    events = []
    disk_teams = Observatory.TeamWatcher.get_state()

    socket =
      socket
      |> assign(:events, events)
      |> assign(:filter_source_app, nil)
      |> assign(:filter_session_id, nil)
      |> assign(:filter_event_type, nil)
      |> assign(:filter_slow, false)
      |> assign(:search_feed, "")
      |> assign(:search_sessions, "")
      |> assign(:search_messages, "")
      |> assign(:search_history, [])
      |> assign(:selected_event, nil)
      |> assign(:selected_task, nil)
      |> assign(:selected_agent, nil)
      |> assign(:expanded_events, [])
      |> assign(:now, DateTime.utc_now())
      |> assign(:page_title, "Observatory")
      |> assign(:view_mode, :command)
      |> assign(:activity_tab, :feed)
      |> assign(:pipeline_tab, :dag)
      |> assign(:forensic_tab, :archive)
      |> assign(:control_tab, :emergency)
      |> assign(:agent_slideout, nil)
      |> assign(:slideout_terminal, "")
      |> assign(:slideout_activity, [])
      |> assign(:expanded_sessions, MapSet.new())
      |> assign(:disk_teams, disk_teams)
      |> assign(:swarm_state, Observatory.SwarmMonitor.get_state())
      |> assign(:protocol_stats, %{})
      |> assign(:selected_dag_task, nil)
      |> assign(:selected_command_agent, nil)
      |> assign(:selected_command_task, nil)
      |> assign(:show_add_project, false)
      |> assign(:selected_team, nil)
      |> assign(:mailbox_counts, %{})
      |> assign(:collapsed_threads, %{})
      |> assign(:show_shortcuts_help, false)
      |> assign(:show_create_task_modal, false)
      |> assign(:inspected_teams, [])
      |> assign(:inspector_layout, :horizontal)
      |> assign(:inspector_maximized, false)
      |> assign(:inspector_size, :default)
      |> assign(:output_mode, :all_live)
      |> assign(:agent_toggles, %{})
      |> assign(:selected_message_target, nil)
      |> assign(:inspector_events, [])
      |> assign(:current_session_id, "operator")
      |> assign(:collapsed_fleet_teams, MapSet.new())
      |> assign(:comms_team_filter, nil)
      |> assign(:dirty, true)
      |> assign(:sidebar_collapsed, false)
      |> assign(:active_tmux_session, nil)
      |> assign(:tmux_output, "")
      |> assign(:tmux_sessions, [])
      # Phase 5 - Fleet Command (task 2)
      |> assign(:throughput_rate, nil)
      |> assign(:cost_heatmap, [])
      |> assign(:node_status, nil)
      |> assign(:latency_metrics, %{})
      |> assign(:mtls_status, "Not configured")
      |> assign(:agent_grid_open, false)
      |> assign(:selected_topology_node, nil)
      # Phase 5 - Session Cluster & Registry (task 3)
      |> assign(:entropy_filter_active, false)
      |> assign(:entropy_threshold, 0.7)
      |> assign(:selected_session_id, nil)
      |> assign(:scratchpad_intents, [])
      |> assign(:feed_panel_open, false)
      |> assign(:messages_panel_open, false)
      |> assign(:tasks_panel_open, false)
      |> assign(:protocols_panel_open, false)
      |> assign(:agent_types, [])
      |> assign(:route_weights, %{})
      |> assign(:capability_sort_field, :agent_type)
      |> assign(:capability_sort_dir, :asc)
      |> assign(:route_weight_errors, %{})
      # Phase 5 - God Mode (task 5)
      |> assign(:kill_switch_confirm_step, nil)
      |> assign(:agent_classes, [])
      |> assign(:instructions_confirm_pending, nil)
      |> assign(:instructions_banner, nil)
      # Phase 5 - Scheduler (task 4)
      |> assign(:cron_jobs, [])
      |> assign(:dlq_entries, [])
      |> assign(:zombie_agents, [])
      # Phase 5 - Forensic (task 4)
      |> assign(:archive_search, "")
      |> assign(:archive_results, [])
      |> assign(:cost_group_by, :agent_id)
      |> assign(:cost_attribution, [])
      |> assign(:webhook_logs, [])
      |> assign(:policy_rules, [])
      |> assign(:forensic_audit_open, false)
      |> assign(:forensic_topology_open, false)
      |> assign(:forensic_entropy_open, false)
      |> assign(:expanded_protocol_items, MapSet.new())
      # Seed gateway data from GenServer queries
      |> seed_gateway_assigns()
      |> recompute()

    # Subscribe to mailbox channels for all active sessions
    if connected?(socket) do
      subscribe_to_mailboxes(socket.assigns.sessions)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    nav_view =
      case params["view"] do
        "fleet" -> :fleet
        "protocols" -> :fleet
        _ -> :pipeline
      end

    {:noreply, assign(socket, :nav_view, nav_view)}
  end

  @impl true
  def handle_info({:new_event, event}, socket) do
    events = [event | socket.assigns.events] |> Enum.take(@max_events)

    {:noreply,
     socket
     |> assign(:events, events)
     |> assign(:now, DateTime.utc_now())
     |> recompute()}
  end

  def handle_info({:heartbeat, _count}, socket) do
    socket =
      case socket.assigns[:active_tmux_session] do
        nil ->
          socket

        session ->
          case Observatory.Gateway.Channels.Tmux.capture_pane(session, lines: 80) do
            {:ok, output} -> assign(socket, :tmux_output, output)
            {:error, _} -> assign(socket, active_tmux_session: nil, tmux_output: "Session ended.")
          end
      end

    {:noreply, socket}
  end

  def handle_info({:teams_updated, teams}, socket) do
    # teams arrives as a map (%{name => struct}) from TeamWatcher -- keep as map
    # since merge_team_sources/2 expects Map.values() on it
    disk_teams =
      case teams do
        t when is_map(t) -> t
        _ -> %{}
      end

    # Prune inspected teams that no longer exist
    team_names = disk_teams |> Map.values() |> Enum.map(fn t -> t[:name] || t["name"] end) |> MapSet.new()

    pruned =
      Enum.filter(socket.assigns.inspected_teams, fn t -> MapSet.member?(team_names, t.name) end)

    {:noreply,
     socket |> assign(:disk_teams, disk_teams) |> assign(:inspected_teams, pruned) |> recompute()}
  end

  def handle_info({:new_mailbox_message, message}, socket) do
    handle_new_mailbox_message(message, socket)
  end

  def handle_info({:swarm_state, state}, socket) do
    {:noreply, socket |> assign(:swarm_state, state) |> recompute()}
  end

  def handle_info({:protocol_update, stats}, socket) do
    {:noreply, socket |> assign(:protocol_stats, stats) |> assign(:dirty, true)}
  end

  def handle_info({:message_read, _read_info}, socket) do
    {:noreply, socket |> assign(:protocol_stats, Observatory.ProtocolTracker.get_stats()) |> assign(:dirty, true)}
  end

  def handle_info({:agent_crashed, session_id, team_name, reassigned_count}, socket) do
    {:noreply,
     handle_agent_crashed(session_id, team_name, reassigned_count, socket) |> recompute()}
  end

  # Gateway PubSub handlers
  def handle_info({:decision_log, _log} = msg, socket) do
    {:noreply, handle_gateway_info(msg, socket) |> recompute()}
  end

  def handle_info({:schema_violation, _event} = msg, socket) do
    {:noreply, handle_gateway_info(msg, socket) |> recompute()}
  end

  def handle_info({:node_state_update, _data} = msg, socket) do
    {:noreply, handle_gateway_info(msg, socket) |> recompute()}
  end

  def handle_info({:dead_letter, _delivery} = msg, socket) do
    {:noreply, handle_gateway_info(msg, socket) |> recompute()}
  end

  def handle_info({:capability_update, _agents} = msg, socket) do
    {:noreply, handle_gateway_info(msg, socket) |> recompute()}
  end

  def handle_info(%{event_type: "entropy_alert"} = msg, socket) do
    {:noreply, handle_gateway_info(msg, socket) |> recompute()}
  end

  def handle_info(%{session_id: _sid, state: _state} = msg, socket)
      when is_map_key(msg, :session_id) and is_map_key(msg, :state) and map_size(msg) == 2 do
    {:noreply, handle_gateway_info(msg, socket) |> recompute()}
  end

  # Fleet topology refresh from TopologyBuilder
  def handle_info(%{nodes: _nodes, edges: _edges} = msg, socket)
      when is_map_key(msg, :nodes) and is_map_key(msg, :edges) do
    {:noreply, handle_gateway_info(msg, socket)}
  end

  # Per-session DAG delta from CausalDAG
  def handle_info(%{event: "dag_delta"} = msg, socket) do
    {:noreply, handle_gateway_info(msg, socket)}
  end

  def handle_info({:terminal_output, session_id, output}, socket) do
    if socket.assigns.agent_slideout && socket.assigns.agent_slideout[:session_id] == session_id do
      {:noreply, assign(socket, :slideout_terminal, output)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("filter", p, s), do: {:noreply, handle_filter(p, s) |> recompute()}

  def handle_event("clear_filters", _p, s),
    do: {:noreply, handle_clear_filters(s) |> recompute()}

  def handle_event("apply_preset", %{"preset" => preset}, s),
    do: {:noreply, handle_apply_preset(preset, s) |> recompute()}

  def handle_event("search_feed", %{"q" => q}, s),
    do: {:noreply, handle_search_feed(q, s) |> recompute()}

  def handle_event("search_sessions", %{"q" => q}, s),
    do: {:noreply, handle_search_sessions(q, s) |> recompute()}

  def handle_event("select_event", %{"id" => id}, socket) do
    cur = socket.assigns.selected_event
    sel = if cur && cur.id == id, do: nil, else: Enum.find(socket.assigns.events, &(&1.id == id))
    {:noreply, socket |> clear_selections() |> assign(:selected_event, sel) |> recompute()}
  end

  def handle_event("select_task", %{"id" => id}, socket) do
    cur = socket.assigns.selected_task

    sel =
      if cur && cur[:id] == id,
        do: nil,
        else: Enum.find(socket.assigns.active_tasks, &(&1[:id] == id))

    {:noreply, socket |> clear_selections() |> assign(:selected_task, sel) |> recompute()}
  end

  def handle_event("select_agent", %{"id" => id}, socket) do
    cur = socket.assigns.selected_agent

    sel =
      if cur && cur[:agent_id] == id, do: nil, else: find_agent_by_id(socket.assigns.teams, id)

    {:noreply, socket |> clear_selections() |> assign(:selected_agent, sel) |> recompute()}
  end

  def handle_event(e, p, s) when e in ["close_detail", "close_task_detail"] do
    h =
      if e == "close_detail", do: handle_close_detail(p, s), else: handle_close_task_detail(p, s)

    {:noreply, h |> recompute()}
  end

  def handle_event("filter_tool", %{"tool" => t}, s),
    do: {:noreply, handle_filter_tool(t, s) |> recompute()}

  def handle_event("filter_tool_use_id", %{"tuid" => t}, s),
    do: {:noreply, handle_filter_tool_use_id(t, s) |> recompute()}

  def handle_event("clear_events", _p, s),
    do: {:noreply, s |> assign(:events, []) |> recompute()}

  def handle_event("filter_session", %{"sid" => sid}, s),
    do: {:noreply, handle_filter_session(sid, s) |> recompute()}

  def handle_event("set_view", %{"mode" => m}, s),
    do: {:noreply, handle_set_view(m, s) |> recompute()}

  def handle_event("restore_view_mode", p, s),
    do:
      {:noreply,
       ObservatoryWeb.DashboardNavigationHandlers.handle_event("restore_view_mode", p, s)
       |> recompute()}

  def handle_event("restore_state", p, s),
    do: {:noreply, handle_restore_state(p, s) |> recompute()}

  def handle_event("select_team", %{"name" => name}, s) do
    sel = if s.assigns.selected_team == name, do: nil, else: name
    {:noreply, s |> assign(:selected_team, sel) |> recompute()}
  end

  def handle_event("filter_team", %{"name" => n}, s),
    do: {:noreply, handle_filter_team(n, s) |> recompute()}

  def handle_event("filter_agent", %{"session_id" => sid}, s),
    do: {:noreply, handle_filter_agent(sid, s) |> recompute()}

  def handle_event("send_agent_message", p, s), do: handle_send_agent_message(p, s)
  def handle_event("send_team_broadcast", p, s), do: handle_send_team_broadcast(p, s)
  def handle_event("push_context", p, s), do: handle_push_context(p, s)

  def handle_event("toggle_shortcuts_help", p, s),
    do: {:noreply, handle_toggle_shortcuts_help(p, s) |> recompute()}

  def handle_event("toggle_create_task_modal", p, s),
    do: {:noreply, handle_toggle_create_task_modal(p, s) |> recompute()}

  def handle_event("toggle_event_detail", p, s),
    do: {:noreply, handle_toggle_event_detail(p, s) |> recompute()}

  def handle_event("focus_agent", p, s),
    do: {:noreply, handle_focus_agent(p, s) |> recompute()}

  def handle_event("close_agent_focus", p, s),
    do: {:noreply, handle_close_agent_focus(p, s) |> recompute()}

  def handle_event("toggle_session_collapse", %{"session_id" => sid}, s) do
    expanded = s.assigns.expanded_sessions

    expanded =
      if MapSet.member?(expanded, sid),
        do: MapSet.delete(expanded, sid),
        else: MapSet.put(expanded, sid)

    {:noreply, assign(s, :expanded_sessions, expanded)}
  end

  def handle_event("expand_all", _p, s) do
    all_keys =
      s.assigns.feed_groups
      |> Enum.flat_map(fn g ->
        item_keys =
          g.turns
          |> Enum.flat_map(fn
            %{type: :turn} = turn ->
              turn_key = "turn:#{turn.first_event_id}"
              phase_keys = Enum.map(turn.phases, fn p -> "phase:#{turn.first_event_id}:#{p.index}" end)
              [turn_key | phase_keys]

            %{type: :preamble} = preamble ->
              first = List.first(preamble.events)
              preamble_key = "preamble:#{first.id}"
              phase_keys = Enum.map(preamble.phases, fn p -> "phase:preamble:#{p.index}" end)
              [preamble_key | phase_keys]

            _ ->
              []
          end)

        [g.session_id | item_keys]
      end)
      |> MapSet.new()

    {:noreply, assign(s, :expanded_sessions, all_keys)}
  end

  def handle_event("collapse_all", _p, s) do
    {:noreply, assign(s, :expanded_sessions, MapSet.new())}
  end

  def handle_event("pause_agent", p, s),
    do:
      {:noreply,
       ObservatoryWeb.DashboardSessionControlHandlers.handle_pause_agent(p, s)
       |> recompute()}

  def handle_event("resume_agent", p, s),
    do:
      {:noreply,
       ObservatoryWeb.DashboardSessionControlHandlers.handle_resume_agent(p, s)
       |> recompute()}

  def handle_event("shutdown_agent", p, s),
    do:
      {:noreply,
       ObservatoryWeb.DashboardSessionControlHandlers.handle_shutdown_agent(p, s)
       |> recompute()}

  def handle_event("create_task", p, s) do
    case handle_create_task(p, s) do
      {:noreply, upd} ->
        {:noreply, upd |> assign(:show_create_task_modal, false) |> recompute()}

      other ->
        other
    end
  end

  def handle_event("update_task_status", p, s) do
    case handle_update_task_status(p, s) do
      {:noreply, upd} -> {:noreply, upd |> recompute()}
      other -> other
    end
  end

  def handle_event("reassign_task", p, s) do
    case handle_reassign_task(p, s) do
      {:noreply, upd} -> {:noreply, upd |> recompute()}
      other -> other
    end
  end

  def handle_event("delete_task", p, s) do
    case handle_delete_task(p, s) do
      {:noreply, upd} -> {:noreply, upd |> recompute()}
      other -> other
    end
  end

  def handle_event("keyboard_escape", p, s),
    do: {:noreply, handle_keyboard_escape(p, s) |> recompute()}

  def handle_event("keyboard_navigate", p, s),
    do: {:noreply, handle_keyboard_navigate(p, s) |> recompute()}

  def handle_event("add_note", p, s) do
    {:noreply, res} = handle_add_note(p, s)
    {:noreply, res |> recompute()}
  end

  def handle_event("delete_note", p, s) do
    {:noreply, res} = handle_delete_note(p, s)
    {:noreply, res |> recompute()}
  end

  def handle_event("search_messages", p, s),
    do: {:noreply, handle_search_messages(p, s) |> recompute()}

  def handle_event("toggle_thread", p, s),
    do: {:noreply, handle_toggle_thread(p, s) |> recompute()}

  def handle_event("expand_all_threads", _p, s),
    do: {:noreply, handle_expand_all_threads(s) |> recompute()}

  def handle_event("collapse_all_threads", _p, s),
    do: {:noreply, handle_collapse_all_threads(s) |> recompute()}

  # Inspector handlers
  def handle_event("inspect_team", p, s),
    do: {:noreply, handle_inspect_team(p, s) |> recompute()}

  def handle_event("remove_from_inspector", p, s),
    do: {:noreply, handle_remove_from_inspector(p, s) |> recompute()}

  def handle_event("close_all_inspector", _p, s),
    do: {:noreply, handle_close_all_inspector(s) |> recompute()}

  def handle_event("toggle_inspector_layout", _p, s),
    do: {:noreply, handle_toggle_inspector_layout(s) |> recompute()}

  def handle_event("toggle_maximize_inspector", _p, s),
    do: {:noreply, handle_toggle_maximize_inspector(s) |> recompute()}

  def handle_event("set_inspector_size", p, s),
    do: {:noreply, handle_set_inspector_size(p, s) |> recompute()}

  def handle_event("set_output_mode", p, s),
    do: {:noreply, handle_set_output_mode(p, s) |> recompute()}

  def handle_event("toggle_agent_output", p, s),
    do: {:noreply, handle_toggle_agent_output(p, s) |> recompute()}

  def handle_event("set_message_target", p, s),
    do: {:noreply, handle_set_message_target(p, s) |> recompute()}

  def handle_event("send_targeted_message", p, s),
    do: {:noreply, handle_send_targeted_message(p, s) |> recompute()}

  def handle_event("toggle_fleet_team", %{"name" => team_name}, s) do
    collapsed = s.assigns.collapsed_fleet_teams

    collapsed =
      if MapSet.member?(collapsed, team_name),
        do: MapSet.delete(collapsed, team_name),
        else: MapSet.put(collapsed, team_name)

    {:noreply, assign(s, :collapsed_fleet_teams, collapsed)}
  end

  def handle_event("set_comms_filter", %{"team" => ""}, s) do
    {:noreply, assign(s, :comms_team_filter, nil)}
  end

  def handle_event("set_comms_filter", %{"team" => team_name}, s) do
    current = s.assigns.comms_team_filter
    new_filter = if current == team_name, do: nil, else: team_name
    {:noreply, assign(s, :comms_team_filter, new_filter)}
  end

  def handle_event("connect_tmux", %{"session" => session_name}, socket) do
    output =
      case Observatory.Gateway.Channels.Tmux.capture_pane(session_name, lines: 80) do
        {:ok, text} -> text
        {:error, _} -> "Failed to capture pane output."
      end

    {:noreply,
     socket
     |> assign(active_tmux_session: session_name, tmux_output: output)
     |> push_event("toast", %{message: "Connected to #{session_name}", type: "success"})}
  end

  def handle_event("disconnect_tmux", _params, socket) do
    {:noreply, assign(socket, active_tmux_session: nil, tmux_output: "")}
  end

  def handle_event("send_tmux_keys", %{"keys" => keys}, socket) do
    case socket.assigns.active_tmux_session do
      nil ->
        {:noreply, socket}

      session ->
        args =
          Observatory.Gateway.Channels.Tmux.socket_args() ++
            ["send-keys", "-t", session, keys, "Enter"]

        System.cmd("tmux", args, stderr_to_stdout: true)

        # Refresh output after sending keys (event-driven, not polled)
        output =
          case Observatory.Gateway.Channels.Tmux.capture_pane(session, lines: 80) do
            {:ok, text} -> text
            {:error, _} -> socket.assigns.tmux_output
          end

        {:noreply, assign(socket, :tmux_output, output)}
    end
  end

  def handle_event("kill_tmux_session", _params, socket) do
    case socket.assigns.active_tmux_session do
      nil ->
        {:noreply, socket}

      session ->
        args =
          Observatory.Gateway.Channels.Tmux.socket_args() ++
            ["kill-session", "-t", session]

        System.cmd("tmux", args, stderr_to_stdout: true)

        {:noreply,
         socket
         |> assign(active_tmux_session: nil, tmux_output: "")
         |> push_event("toast", %{message: "Killed #{session}", type: "warning"})}
    end
  end

  @observatory_socket Path.expand("~/.observatory/tmux/obs.sock")

  def handle_event("launch_session", %{"cwd" => cwd} = params, socket) when cwd != "" do
    session_name = "obs-#{:os.system_time(:second)}"
    command = params["command"] || "claude"

    # Ensure socket directory exists
    File.mkdir_p!(Path.dirname(@observatory_socket))

    # Launch on Observatory's tmux server, clearing CLAUDECODE to allow nested sessions
    socket_args = Observatory.Gateway.Channels.Tmux.socket_args()

    case System.cmd("tmux", socket_args ++ [
           "new-session", "-d", "-s", session_name, "-c", cwd,
           "env", "-u", "CLAUDECODE", command
         ], stderr_to_stdout: true) do
      {_output, 0} ->
        {:noreply,
         push_event(socket, "toast", %{
           message: "Launched #{session_name} in #{Path.basename(cwd)}",
           type: "success"
         })}

      {error, _code} ->
        {:noreply,
         push_event(socket, "toast", %{
           message: "Launch failed: #{String.slice(error, 0, 80)}",
           type: "error"
         })}
    end
  end

  def handle_event("launch_session", _params, socket) do
    {:noreply, push_event(socket, "toast", %{message: "Select a project first", type: "error"})}
  end

  # Swarm handlers
  def handle_event("select_project", p, s),
    do: {:noreply, handle_select_project(p, s) |> recompute()}

  def handle_event("heal_task", p, s),
    do: {:noreply, handle_heal_task(p, s) |> recompute()}

  def handle_event("reset_all_stale", _p, s),
    do: {:noreply, handle_reset_all_stale(%{}, s) |> recompute()}

  def handle_event("run_health_check", _p, s),
    do: {:noreply, handle_run_health_check(%{}, s) |> recompute()}

  def handle_event("reassign_swarm_task", p, s),
    do: {:noreply, handle_reassign_swarm_task(p, s) |> recompute()}

  def handle_event("claim_swarm_task", p, s),
    do: {:noreply, handle_claim_swarm_task(p, s) |> recompute()}

  def handle_event("trigger_gc", p, s),
    do: {:noreply, handle_trigger_gc(p, s) |> recompute()}

  def handle_event("select_dag_node", p, s),
    do: {:noreply, handle_select_dag_node(p, s) |> recompute()}

  def handle_event("select_command_agent", p, s),
    do: {:noreply, handle_select_command_agent(p, s) |> recompute()}

  def handle_event("node_selected", %{"trace_id" => trace_id}, socket) do
    # Look up session info from events by matching session_id or trace_id
    events = socket.assigns.events
    now = socket.assigns.now

    session_events =
      Enum.filter(events, fn e -> e.session_id == trace_id end)

    info =
      if session_events != [] do
        sorted = Enum.sort_by(session_events, & &1.inserted_at, {:desc, DateTime})
        latest = hd(sorted)
        ended? = Enum.any?(session_events, &(&1.hook_event_type == :SessionEnd))

        model =
          Enum.find_value(session_events, fn e ->
            if e.hook_event_type == :SessionStart,
              do: (e.payload || %{})["model"] || e.model_name
          end) || Enum.find_value(session_events, & &1.model_name)

        status =
          cond do
            ended? -> :ended
            DateTime.diff(now, latest.inserted_at, :second) > 120 -> :idle
            true -> :active
          end

        first = Enum.min_by(session_events, & &1.inserted_at, DateTime)
        dur_sec = DateTime.diff(now, first.inserted_at, :second)

        %{
          session_id: trace_id,
          model: model,
          status: status,
          event_count: length(session_events),
          tool_count: Enum.count(session_events, &(&1.hook_event_type == :PreToolUse)),
          source_app: latest.source_app,
          cwd: latest.cwd || Enum.find_value(session_events, & &1.cwd),
          last_tool: latest.tool_name,
          duration: session_duration_sec(dur_sec)
        }
      else
        %{session_id: trace_id, status: :unknown, event_count: 0}
      end

    {:noreply, assign(socket, :selected_topology_node, info)}
  end

  def handle_event("clear_topology_selection", _p, s),
    do: {:noreply, assign(s, :selected_topology_node, nil)}

  def handle_event("clear_command_selection", _p, s),
    do: {:noreply, handle_clear_command_selection(%{}, s) |> recompute()}

  def handle_event("send_command_message", %{"to" => to, "content" => content} = p, s) do
    socket = handle_send_command_message(p, s) |> recompute()

    socket =
      if content != "" do
        short = String.slice(to, 0, 8)
        push_event(socket, "toast", %{message: "Sent to #{short}", type: "success"})
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("toggle_sidebar", _p, s) do
    new_val = !s.assigns.sidebar_collapsed

    {:noreply,
     s
     |> assign(:sidebar_collapsed, new_val)
     |> push_event("filters_changed", %{sidebar_collapsed: to_string(new_val)})}
  end

  # Sub-tab switching within consolidated screens
  def handle_event("set_sub_tab", %{"screen" => screen, "tab" => tab}, s) do
    key =
      case screen do
        "activity" -> :activity_tab
        "pipeline" -> :pipeline_tab
        "forensic" -> :forensic_tab
        "control" -> :control_tab
        _ -> nil
      end

    if key do
      {:noreply, s |> assign(key, String.to_existing_atom(tab)) |> recompute()}
    else
      {:noreply, s}
    end
  end

  # Agent slideout panel (right side panel in Command screen)
  def handle_event("open_agent_slideout", %{"session_id" => sid}, s) do
    # Unwatch previous agent if any
    if s.assigns.agent_slideout do
      prev_sid = s.assigns.agent_slideout[:session_id]
      if prev_sid, do: Phoenix.PubSub.unsubscribe(Observatory.PubSub, "agent:#{prev_sid}:activity")
      if prev_sid, do: Observatory.Gateway.AgentRegistry.unwatch(prev_sid)
    end

    agent = Observatory.Gateway.AgentRegistry.get(sid)
    Phoenix.PubSub.subscribe(Observatory.PubSub, "agent:#{sid}:activity")
    Observatory.Gateway.AgentRegistry.watch(sid)

    # Build initial activity stream
    activity = build_slideout_activity(sid, s.assigns.events, s.assigns.messages)

    {:noreply,
     s
     |> assign(:agent_slideout, agent || %{session_id: sid})
     |> assign(:slideout_terminal, "")
     |> assign(:slideout_activity, activity)
     |> recompute()}
  end

  def handle_event("close_agent_slideout", _p, s) do
    if s.assigns.agent_slideout do
      sid = s.assigns.agent_slideout[:session_id]
      if sid, do: Phoenix.PubSub.unsubscribe(Observatory.PubSub, "agent:#{sid}:activity")
      if sid, do: Observatory.Gateway.AgentRegistry.unwatch(sid)
    end

    {:noreply,
     s
     |> assign(:agent_slideout, nil)
     |> assign(:slideout_terminal, "")
     |> assign(:slideout_activity, [])}
  end

  def handle_event("toggle_add_project", _p, s),
    do:
      {:noreply, s |> assign(:show_add_project, !s.assigns.show_add_project) |> recompute()}

  def handle_event("add_project", p, s),
    do:
      {:noreply,
       handle_add_project(p, s) |> assign(:show_add_project, false) |> recompute()}

  # Phase 5 - Fleet Command handlers
  def handle_event("toggle_agent_grid", _p, s) do
    {:noreply, s |> assign(:agent_grid_open, !s.assigns.agent_grid_open) |> recompute()}
  end

  # Phase 5 - Session Cluster & Registry handlers
  def handle_event("toggle_entropy_filter", _p, s) do
    {:noreply, s |> assign(:entropy_filter_active, !s.assigns.entropy_filter_active) |> recompute()}
  end

  def handle_event("select_session", %{"session_id" => sid}, s) do
    s = subscribe_session_dag(s, sid)
    {:noreply, s |> assign(:selected_session_id, sid) |> recompute()}
  end

  def handle_event("toggle_subpanel", %{"panel" => panel}, s) do
    key = String.to_existing_atom("#{panel}_panel_open")
    {:noreply, s |> assign(key, !Map.get(s.assigns, key, false)) |> recompute()}
  end

  def handle_event("sort_capability_directory", %{"field" => field}, s) do
    field_atom = String.to_existing_atom(field)
    new_dir = if s.assigns.capability_sort_field == field_atom and s.assigns.capability_sort_dir == :asc, do: :desc, else: :asc
    {:noreply, s |> assign(:capability_sort_field, field_atom) |> assign(:capability_sort_dir, new_dir) |> recompute()}
  end

  def handle_event("update_route_weight", %{"agent_type" => agent_type, "weight" => weight_str}, s) do
    case Integer.parse(weight_str) do
      {w, ""} when w >= 0 and w <= 100 ->
        weights = Map.put(s.assigns.route_weights, agent_type, w)
        {:noreply, s |> assign(:route_weights, weights) |> assign(:route_weight_errors, Map.delete(s.assigns.route_weight_errors, agent_type)) |> recompute()}
      _ ->
        errors = Map.put(s.assigns.route_weight_errors, agent_type, "Must be 0-100")
        {:noreply, s |> assign(:route_weight_errors, errors) |> recompute()}
    end
  end

  # Phase 5 - Scheduler handlers
  def handle_event("retry_dlq_entry", %{"entry_id" => entry_id}, s) do
    dlq = Enum.map(s.assigns.dlq_entries, fn entry ->
      if Map.get(entry, :id) == entry_id, do: Map.put(entry, :state, "pending"), else: entry
    end)
    {:noreply, s |> assign(:dlq_entries, dlq) |> recompute()}
  end

  # Phase 5 - Forensic handlers
  def handle_event("search_archive", %{"q" => query}, s) do
    results = Enum.filter(s.assigns.events, fn ev ->
      query != "" and String.contains?(String.downcase(inspect(ev)), String.downcase(query))
    end)
    {:noreply, s |> assign(:archive_search, query) |> assign(:archive_results, results) |> recompute()}
  end

  def handle_event("set_cost_group_by", %{"field" => field}, s) do
    {:noreply, s |> assign(:cost_group_by, String.to_existing_atom(field)) |> recompute()}
  end

  def handle_event("add_policy_rule", %{"name" => name, "condition" => condition, "action" => action}, s) do
    rule = %{id: System.unique_integer([:positive]), name: name, condition: condition, action: action, enabled: true}
    {:noreply, s |> assign(:policy_rules, [rule | s.assigns.policy_rules]) |> recompute()}
  end

  def handle_event("toggle_forensic_panel", %{"panel" => panel}, s) do
    key = String.to_existing_atom("forensic_#{panel}_open")
    {:noreply, s |> assign(key, !Map.get(s.assigns, key, false)) |> recompute()}
  end

  def handle_event("toggle_protocol_item", %{"id" => id}, s) do
    expanded = s.assigns.expanded_protocol_items

    expanded =
      if MapSet.member?(expanded, id),
        do: MapSet.delete(expanded, id),
        else: MapSet.put(expanded, id)

    {:noreply, assign(s, :expanded_protocol_items, expanded)}
  end

  # Phase 5 - God Mode handlers (delegated to DashboardSessionControlHandlers)
  def handle_event("kill_switch_click", p, s) do
    {:noreply, apply(ObservatoryWeb.DashboardSessionControlHandlers, :handle_kill_switch_click, [p, s]) |> recompute()}
  end

  def handle_event("kill_switch_first_confirm", p, s) do
    {:noreply, apply(ObservatoryWeb.DashboardSessionControlHandlers, :handle_kill_switch_first_confirm, [p, s]) |> recompute()}
  end

  def handle_event("kill_switch_second_confirm", p, s) do
    {:noreply, apply(ObservatoryWeb.DashboardSessionControlHandlers, :handle_kill_switch_second_confirm, [p, s]) |> recompute()}
  end

  def handle_event("kill_switch_cancel", p, s) do
    {:noreply, apply(ObservatoryWeb.DashboardSessionControlHandlers, :handle_kill_switch_cancel, [p, s]) |> recompute()}
  end

  def handle_event("push_instructions_intent", p, s) do
    {:noreply, apply(ObservatoryWeb.DashboardSessionControlHandlers, :handle_push_instructions_intent, [p, s]) |> recompute()}
  end

  def handle_event("push_instructions_confirm", p, s) do
    {:noreply, apply(ObservatoryWeb.DashboardSessionControlHandlers, :handle_push_instructions_confirm, [p, s]) |> recompute()}
  end

  def handle_event("push_instructions_cancel", p, s) do
    {:noreply, apply(ObservatoryWeb.DashboardSessionControlHandlers, :handle_push_instructions_cancel, [p, s]) |> recompute()}
  end

  # Navigation handlers
  def handle_event(e, p, s)
      when e in [
             "jump_to_timeline",
             "jump_to_feed",
             "jump_to_agents",
             "jump_to_tasks",
             "select_timeline_event",
             "filter_agent_tasks",
             "filter_analytics_tool"
           ] do
    ObservatoryWeb.DashboardNavigationHandlers.handle_event(e, p, s)
    |> then(&{:noreply, recompute(&1)})
  end

  defp find_agent_by_id(teams, agent_id) do
    teams |> Enum.flat_map(& &1.members) |> Enum.find(&(&1[:agent_id] == agent_id))
  end

  defp clear_selections(socket) do
    socket
    |> assign(:selected_event, nil)
    |> assign(:selected_task, nil)
    |> assign(:selected_agent, nil)
  end

  defp build_slideout_activity(session_id, events, messages) do
    # Hook events for this agent
    event_items =
      events
      |> Enum.filter(fn e -> e.session_id == session_id end)
      |> Enum.map(fn e ->
        %{
          type: :event,
          timestamp: e.inserted_at,
          content: "#{e.hook_event_type}#{if e.tool_name, do: " - #{e.tool_name}", else: ""}",
          id: "ev-#{e.id}"
        }
      end)

    # Messages involving this agent
    message_items =
      messages
      |> Enum.filter(fn m ->
        m[:session_id] == session_id || m[:to] == session_id || m[:from] == session_id
      end)
      |> Enum.map(fn m ->
        %{
          type: :message,
          timestamp: m[:timestamp] || m[:inserted_at],
          content: m[:content] || m[:message] || "",
          id: "msg-#{m[:id] || :erlang.unique_integer([:positive])}"
        }
      end)

    (event_items ++ message_items)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(100)
  end

end
