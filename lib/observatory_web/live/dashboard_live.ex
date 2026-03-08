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
  import ObservatoryWeb.DashboardSessionControlHandlers
  import ObservatoryWeb.DashboardTmuxHandlers
  import ObservatoryWeb.DashboardState, only: [recompute: 1, default_assigns: 1]

  alias ObservatoryWeb.DashboardPhase5Handlers, as: P5
  alias ObservatoryWeb.DashboardSlideoutHandlers, as: Slideout

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
    end

    disk_teams = Observatory.TeamWatcher.get_state()

    socket =
      socket
      |> assign(default_assigns(disk_teams))
      |> seed_gateway_assigns()
      |> recompute()

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

  # ── handle_info ──────────────────────────────────────────────────────

  @impl true
  def handle_info({:new_event, event}, socket) do
    events = [event | socket.assigns.events] |> Enum.take(@max_events)
    {:noreply, socket |> assign(:events, events) |> assign(:now, DateTime.utc_now()) |> recompute()}
  end

  def handle_info({:heartbeat, _count}, socket) do
    socket =
      case socket.assigns[:active_tmux_session] do
        nil -> socket
        session ->
          case Observatory.Gateway.Channels.Tmux.capture_pane(session, lines: 80) do
            {:ok, output} -> assign(socket, :tmux_output, output)
            {:error, _} -> assign(socket, active_tmux_session: nil, tmux_output: "Session ended.")
          end
      end

    {:noreply, socket}
  end

  def handle_info({:teams_updated, teams}, socket) do
    disk_teams = if is_map(teams), do: teams, else: %{}

    team_names =
      disk_teams |> Map.values() |> Enum.map(fn t -> t[:name] || t["name"] end) |> MapSet.new()

    pruned =
      Enum.filter(socket.assigns.inspected_teams, fn t -> MapSet.member?(team_names, t.name) end)

    {:noreply,
     socket |> assign(:disk_teams, disk_teams) |> assign(:inspected_teams, pruned) |> recompute()}
  end

  def handle_info({:new_mailbox_message, message}, socket),
    do: handle_new_mailbox_message(message, socket)

  def handle_info({:swarm_state, state}, socket),
    do: {:noreply, socket |> assign(:swarm_state, state) |> recompute()}

  def handle_info({:protocol_update, stats}, socket),
    do: {:noreply, socket |> assign(:protocol_stats, stats) |> assign(:dirty, true)}

  def handle_info({:message_read, _}, socket),
    do:
      {:noreply,
       socket
       |> assign(:protocol_stats, Observatory.ProtocolTracker.get_stats())
       |> assign(:dirty, true)}

  def handle_info({:agent_crashed, sid, team, count}, socket),
    do: {:noreply, handle_agent_crashed(sid, team, count, socket) |> recompute()}

  def handle_info({:terminal_output, session_id, output}, socket) do
    if socket.assigns.agent_slideout && socket.assigns.agent_slideout[:session_id] == session_id do
      {:noreply, assign(socket, :slideout_terminal, output)}
    else
      {:noreply, socket}
    end
  end

  # Gateway PubSub (topology, DAG deltas, decisions, violations, etc.)
  def handle_info(msg, socket) when is_tuple(msg) and elem(msg, 0) in [
    :decision_log, :schema_violation, :node_state_update, :dead_letter, :capability_update
  ] do
    {:noreply, handle_gateway_info(msg, socket) |> recompute()}
  end

  def handle_info(%{event_type: "entropy_alert"} = msg, socket),
    do: {:noreply, handle_gateway_info(msg, socket) |> recompute()}

  def handle_info(%{session_id: _sid, state: _state} = msg, socket)
      when map_size(msg) == 2,
      do: {:noreply, handle_gateway_info(msg, socket) |> recompute()}

  def handle_info(%{nodes: _nodes, edges: _edges} = msg, socket),
    do: {:noreply, handle_gateway_info(msg, socket)}

  def handle_info(%{event: "dag_delta"} = msg, socket),
    do: {:noreply, handle_gateway_info(msg, socket)}

  # ── handle_event: filters & search ───────────────────────────────────

  @impl true
  def handle_event("filter", p, s), do: {:noreply, handle_filter(p, s) |> recompute()}
  def handle_event("clear_filters", _p, s), do: {:noreply, handle_clear_filters(s) |> recompute()}
  def handle_event("apply_preset", %{"preset" => p}, s), do: {:noreply, handle_apply_preset(p, s) |> recompute()}
  def handle_event("search_feed", %{"q" => q}, s), do: {:noreply, handle_search_feed(q, s) |> recompute()}
  def handle_event("search_sessions", %{"q" => q}, s), do: {:noreply, handle_search_sessions(q, s) |> recompute()}
  def handle_event("filter_tool", %{"tool" => t}, s), do: {:noreply, handle_filter_tool(t, s) |> recompute()}
  def handle_event("filter_tool_use_id", %{"tuid" => t}, s), do: {:noreply, handle_filter_tool_use_id(t, s) |> recompute()}
  def handle_event("clear_events", _p, s), do: {:noreply, s |> assign(:events, []) |> recompute()}
  def handle_event("filter_session", %{"sid" => sid}, s), do: {:noreply, handle_filter_session(sid, s) |> recompute()}
  def handle_event("filter_team", %{"name" => n}, s), do: {:noreply, handle_filter_team(n, s) |> recompute()}
  def handle_event("filter_agent", %{"session_id" => sid}, s), do: {:noreply, handle_filter_agent(sid, s) |> recompute()}
  def handle_event("search_messages", p, s), do: {:noreply, handle_search_messages(p, s) |> recompute()}

  # ── handle_event: selection ──────────────────────────────────────────

  def handle_event("select_event", %{"id" => id}, socket) do
    cur = socket.assigns.selected_event
    sel = if cur && cur.id == id, do: nil, else: Enum.find(socket.assigns.events, &(&1.id == id))
    {:noreply, socket |> clear_selections() |> assign(:selected_event, sel) |> recompute()}
  end

  def handle_event("select_task", %{"id" => id}, socket) do
    cur = socket.assigns.selected_task
    sel = if cur && cur[:id] == id, do: nil, else: Enum.find(socket.assigns.active_tasks, &(&1[:id] == id))
    {:noreply, socket |> clear_selections() |> assign(:selected_task, sel) |> recompute()}
  end

  def handle_event("select_agent", %{"id" => id}, socket) do
    cur = socket.assigns.selected_agent
    sel = if cur && cur[:agent_id] == id, do: nil, else: find_agent_by_id(socket.assigns.teams, id)
    {:noreply, socket |> clear_selections() |> assign(:selected_agent, sel) |> recompute()}
  end

  def handle_event("select_team", %{"name" => name}, s) do
    sel = if s.assigns.selected_team == name, do: nil, else: name
    {:noreply, s |> assign(:selected_team, sel) |> recompute()}
  end

  def handle_event(e, p, s) when e in ["close_detail", "close_task_detail"] do
    h = if e == "close_detail", do: handle_close_detail(p, s), else: handle_close_task_detail(p, s)
    {:noreply, h |> recompute()}
  end

  def handle_event("clear_topology_selection", _p, s),
    do: {:noreply, assign(s, :selected_topology_node, nil)}

  def handle_event("clear_command_selection", _p, s),
    do: {:noreply, handle_clear_command_selection(%{}, s) |> recompute()}

  # ── handle_event: view & navigation ──────────────────────────────────

  def handle_event("set_view", %{"mode" => m}, s), do: {:noreply, handle_set_view(m, s) |> recompute()}

  def handle_event("restore_view_mode", p, s) do
    socket = ObservatoryWeb.DashboardNavigationHandlers.handle_event("restore_view_mode", p, s)
    {:noreply, recompute(socket)}
  end

  def handle_event("restore_state", p, s), do: {:noreply, handle_restore_state(p, s) |> recompute()}

  def handle_event("set_sub_tab", %{"screen" => screen, "tab" => tab}, s) do
    key =
      case screen do
        "activity" -> :activity_tab
        "pipeline" -> :pipeline_tab
        "forensic" -> :forensic_tab
        "control" -> :control_tab
        _ -> nil
      end

    if key, do: {:noreply, s |> assign(key, String.to_existing_atom(tab)) |> recompute()}, else: {:noreply, s}
  end

  def handle_event("toggle_sidebar", _p, s) do
    new_val = !s.assigns.sidebar_collapsed
    {:noreply, s |> assign(:sidebar_collapsed, new_val) |> push_event("filters_changed", %{sidebar_collapsed: to_string(new_val)})}
  end

  # ── handle_event: messaging ─────────────────────────────────────────

  def handle_event("send_agent_message", p, s), do: handle_send_agent_message(p, s)
  def handle_event("send_team_broadcast", p, s), do: handle_send_team_broadcast(p, s)
  def handle_event("push_context", p, s), do: handle_push_context(p, s)

  def handle_event("send_command_message", %{"to" => to, "content" => content} = p, s) do
    socket = handle_send_command_message(p, s) |> recompute()
    socket = if content != "", do: push_event(socket, "toast", %{message: "Sent to #{String.slice(to, 0, 8)}", type: "success"}), else: socket
    {:noreply, socket}
  end

  def handle_event("toggle_thread", p, s), do: {:noreply, handle_toggle_thread(p, s) |> recompute()}
  def handle_event("expand_all_threads", _p, s), do: {:noreply, handle_expand_all_threads(s) |> recompute()}
  def handle_event("collapse_all_threads", _p, s), do: {:noreply, handle_collapse_all_threads(s) |> recompute()}

  # ── handle_event: UI toggles ────────────────────────────────────────

  def handle_event("toggle_shortcuts_help", p, s), do: {:noreply, handle_toggle_shortcuts_help(p, s) |> recompute()}
  def handle_event("toggle_create_task_modal", p, s), do: {:noreply, handle_toggle_create_task_modal(p, s) |> recompute()}
  def handle_event("toggle_event_detail", p, s), do: {:noreply, handle_toggle_event_detail(p, s) |> recompute()}
  def handle_event("focus_agent", p, s), do: {:noreply, handle_focus_agent(p, s) |> recompute()}
  def handle_event("close_agent_focus", p, s), do: {:noreply, handle_close_agent_focus(p, s) |> recompute()}
  def handle_event("keyboard_escape", p, s), do: {:noreply, handle_keyboard_escape(p, s) |> recompute()}
  def handle_event("keyboard_navigate", p, s), do: {:noreply, handle_keyboard_navigate(p, s) |> recompute()}
  def handle_event("toggle_add_project", _p, s), do: {:noreply, s |> assign(:show_add_project, !s.assigns.show_add_project) |> recompute()}
  def handle_event("add_project", p, s), do: {:noreply, handle_add_project(p, s) |> assign(:show_add_project, false) |> recompute()}

  # ── handle_event: feed collapse ─────────────────────────────────────

  def handle_event("toggle_session_collapse", %{"session_id" => sid}, s) do
    expanded = s.assigns.expanded_sessions
    expanded = if MapSet.member?(expanded, sid), do: MapSet.delete(expanded, sid), else: MapSet.put(expanded, sid)
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

            _ -> []
          end)

        [g.session_id | item_keys]
      end)
      |> MapSet.new()

    {:noreply, assign(s, :expanded_sessions, all_keys)}
  end

  def handle_event("collapse_all", _p, s), do: {:noreply, assign(s, :expanded_sessions, MapSet.new())}

  # ── handle_event: fleet tree ─────────────────────────────────────────

  def handle_event("toggle_fleet_team", %{"name" => name}, s) do
    collapsed = s.assigns.collapsed_fleet_teams
    collapsed = if MapSet.member?(collapsed, name), do: MapSet.delete(collapsed, name), else: MapSet.put(collapsed, name)
    {:noreply, assign(s, :collapsed_fleet_teams, collapsed)}
  end

  def handle_event("set_comms_filter", %{"team" => ""}, s), do: {:noreply, assign(s, :comms_team_filter, nil)}

  def handle_event("set_comms_filter", %{"team" => team_name}, s) do
    new_filter = if s.assigns.comms_team_filter == team_name, do: nil, else: team_name
    {:noreply, assign(s, :comms_team_filter, new_filter)}
  end

  # ── handle_event: tasks ──────────────────────────────────────────────

  def handle_event("create_task", p, s) do
    case handle_create_task(p, s) do
      {:noreply, upd} -> {:noreply, upd |> assign(:show_create_task_modal, false) |> recompute()}
      other -> other
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

  # ── handle_event: notes ─────────────────────────────────────────────

  def handle_event("add_note", p, s) do
    {:noreply, res} = handle_add_note(p, s)
    {:noreply, res |> recompute()}
  end

  def handle_event("delete_note", p, s) do
    {:noreply, res} = handle_delete_note(p, s)
    {:noreply, res |> recompute()}
  end

  # ── handle_event: session controls ───────────────────────────────────

  def handle_event("pause_agent", p, s), do: {:noreply, handle_pause_agent(p, s) |> recompute()}
  def handle_event("resume_agent", p, s), do: {:noreply, handle_resume_agent(p, s) |> recompute()}
  def handle_event("shutdown_agent", p, s), do: {:noreply, handle_shutdown_agent(p, s) |> recompute()}

  def handle_event("kill_switch_click", p, s), do: {:noreply, handle_kill_switch_click(p, s) |> recompute()}
  def handle_event("kill_switch_first_confirm", p, s), do: {:noreply, handle_kill_switch_first_confirm(p, s) |> recompute()}
  def handle_event("kill_switch_second_confirm", p, s), do: {:noreply, handle_kill_switch_second_confirm(p, s) |> recompute()}
  def handle_event("kill_switch_cancel", p, s), do: {:noreply, handle_kill_switch_cancel(p, s) |> recompute()}
  def handle_event("push_instructions_intent", p, s), do: {:noreply, handle_push_instructions_intent(p, s) |> recompute()}
  def handle_event("push_instructions_confirm", p, s), do: {:noreply, handle_push_instructions_confirm(p, s) |> recompute()}
  def handle_event("push_instructions_cancel", p, s), do: {:noreply, handle_push_instructions_cancel(p, s) |> recompute()}

  # ── handle_event: tmux ──────────────────────────────────────────────

  def handle_event("connect_tmux", p, s), do: {:noreply, handle_connect_tmux(p, s)}
  def handle_event("disconnect_tmux", p, s), do: {:noreply, handle_disconnect_tmux(p, s)}
  def handle_event("send_tmux_keys", p, s), do: {:noreply, handle_send_tmux_keys(p, s)}
  def handle_event("kill_tmux_session", p, s), do: {:noreply, handle_kill_tmux_session(p, s)}
  def handle_event("launch_session", p, s), do: {:noreply, handle_launch_session(p, s)}

  # ── handle_event: inspector ─────────────────────────────────────────

  def handle_event("inspect_team", p, s), do: {:noreply, handle_inspect_team(p, s) |> recompute()}
  def handle_event("remove_from_inspector", p, s), do: {:noreply, handle_remove_from_inspector(p, s) |> recompute()}
  def handle_event("close_all_inspector", _p, s), do: {:noreply, handle_close_all_inspector(s) |> recompute()}
  def handle_event("toggle_inspector_layout", _p, s), do: {:noreply, handle_toggle_inspector_layout(s) |> recompute()}
  def handle_event("toggle_maximize_inspector", _p, s), do: {:noreply, handle_toggle_maximize_inspector(s) |> recompute()}
  def handle_event("set_inspector_size", p, s), do: {:noreply, handle_set_inspector_size(p, s) |> recompute()}
  def handle_event("set_output_mode", p, s), do: {:noreply, handle_set_output_mode(p, s) |> recompute()}
  def handle_event("toggle_agent_output", p, s), do: {:noreply, handle_toggle_agent_output(p, s) |> recompute()}
  def handle_event("set_message_target", p, s), do: {:noreply, handle_set_message_target(p, s) |> recompute()}
  def handle_event("send_targeted_message", p, s), do: {:noreply, handle_send_targeted_message(p, s) |> recompute()}

  # ── handle_event: swarm ─────────────────────────────────────────────

  def handle_event("select_project", p, s), do: {:noreply, handle_select_project(p, s) |> recompute()}
  def handle_event("heal_task", p, s), do: {:noreply, handle_heal_task(p, s) |> recompute()}
  def handle_event("reset_all_stale", _p, s), do: {:noreply, handle_reset_all_stale(%{}, s) |> recompute()}
  def handle_event("run_health_check", _p, s), do: {:noreply, handle_run_health_check(%{}, s) |> recompute()}
  def handle_event("reassign_swarm_task", p, s), do: {:noreply, handle_reassign_swarm_task(p, s) |> recompute()}
  def handle_event("claim_swarm_task", p, s), do: {:noreply, handle_claim_swarm_task(p, s) |> recompute()}
  def handle_event("trigger_gc", p, s), do: {:noreply, handle_trigger_gc(p, s) |> recompute()}
  def handle_event("select_dag_node", p, s), do: {:noreply, handle_select_dag_node(p, s) |> recompute()}
  def handle_event("select_command_agent", p, s), do: {:noreply, handle_select_command_agent(p, s) |> recompute()}

  # ── handle_event: slideout + topology node ──────────────────────────

  def handle_event("open_agent_slideout", %{"session_id" => sid}, s),
    do: {:noreply, Slideout.handle_open_agent_slideout(sid, s) |> recompute()}

  def handle_event("close_agent_slideout", _p, s),
    do: {:noreply, Slideout.handle_close_agent_slideout(s)}

  def handle_event("node_selected", %{"trace_id" => trace_id}, s),
    do: {:noreply, Slideout.handle_node_selected(trace_id, s)}

  # ── handle_event: Phase 5 ──────────────────────────────────────────

  def handle_event("toggle_agent_grid", _p, s), do: {:noreply, P5.handle_toggle_agent_grid(s) |> recompute()}
  def handle_event("toggle_entropy_filter", _p, s), do: {:noreply, P5.handle_toggle_entropy_filter(s) |> recompute()}
  def handle_event("select_session", %{"session_id" => sid}, s), do: {:noreply, P5.handle_select_session(sid, s) |> recompute()}
  def handle_event("toggle_subpanel", %{"panel" => panel}, s), do: {:noreply, P5.handle_toggle_subpanel(panel, s) |> recompute()}
  def handle_event("sort_capability_directory", %{"field" => f}, s), do: {:noreply, P5.handle_sort_capability_directory(f, s) |> recompute()}
  def handle_event("update_route_weight", %{"agent_type" => at, "weight" => w}, s), do: {:noreply, P5.handle_update_route_weight(at, w, s) |> recompute()}
  def handle_event("retry_dlq_entry", %{"entry_id" => eid}, s), do: {:noreply, P5.handle_retry_dlq_entry(eid, s) |> recompute()}
  def handle_event("search_archive", %{"q" => q}, s), do: {:noreply, P5.handle_search_archive(q, s) |> recompute()}
  def handle_event("set_cost_group_by", %{"field" => f}, s), do: {:noreply, P5.handle_set_cost_group_by(f, s) |> recompute()}

  def handle_event("add_policy_rule", %{"name" => n, "condition" => c, "action" => a}, s),
    do: {:noreply, P5.handle_add_policy_rule(n, c, a, s) |> recompute()}

  def handle_event("toggle_forensic_panel", %{"panel" => p}, s),
    do: {:noreply, P5.handle_toggle_forensic_panel(p, s) |> recompute()}

  def handle_event("toggle_protocol_item", %{"id" => id}, s) do
    expanded = s.assigns.expanded_protocol_items
    expanded = if MapSet.member?(expanded, id), do: MapSet.delete(expanded, id), else: MapSet.put(expanded, id)
    {:noreply, assign(s, :expanded_protocol_items, expanded)}
  end

  # ── handle_event: navigation (full-module, cannot import) ───────────

  def handle_event(e, p, s)
      when e in [
             "jump_to_timeline", "jump_to_feed", "jump_to_agents", "jump_to_tasks",
             "select_timeline_event", "filter_agent_tasks", "filter_analytics_tool"
           ] do
    ObservatoryWeb.DashboardNavigationHandlers.handle_event(e, p, s)
    |> then(&{:noreply, recompute(&1)})
  end

  # ── Private helpers ─────────────────────────────────────────────────

  defp find_agent_by_id(teams, agent_id) do
    teams |> Enum.flat_map(& &1.members) |> Enum.find(&(&1[:agent_id] == agent_id))
  end

  defp clear_selections(socket) do
    socket
    |> assign(:selected_event, nil)
    |> assign(:selected_task, nil)
    |> assign(:selected_agent, nil)
  end
end
