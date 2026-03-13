defmodule IchorWeb.DashboardLive do
  use IchorWeb, :live_view

  import IchorWeb.DashboardDataHelpers, only: [unique_values: 2]
  import IchorWeb.DashboardFormatHelpers, only: [build_export_url: 4]
  import IchorWeb.DashboardAgentHelpers, only: [agent_tasks: 2]
  import IchorWeb.DashboardAgentActivityHelpers, only: [agent_events: 2]
  import IchorWeb.DashboardState, only: [recompute: 1, recompute_view: 1, default_assigns: 1]

  import IchorWeb.DashboardGatewayHandlers,
    only: [subscribe_gateway_topics: 0, seed_gateway_assigns: 1]

  import IchorWeb.DashboardWorkshopHandlers,
    only: [list_blueprints: 0, list_agent_types: 0, push_ws_state: 1]

  import IchorWeb.DashboardMessagingHandlers, only: [subscribe_to_mailboxes: 1]

  alias Ichor.Signals.{Buffer, Catalog}

  alias IchorWeb.{
    DashboardArchonHandlers,
    DashboardFeedHandlers,
    DashboardFilterHandlers,
    DashboardFleetTreeHandlers,
    DashboardInfoHandlers,
    DashboardMesHandlers,
    DashboardMessagingHandlers,
    DashboardNavigationHandlers,
    DashboardNotesHandlers,
    DashboardPhase5Handlers,
    DashboardSelectionHandlers,
    DashboardSessionControlHandlers,
    DashboardSlideoutHandlers,
    DashboardSpawnHandlers,
    DashboardSwarmHandlers,
    DashboardTaskHandlers,
    DashboardTeamInspectorHandlers,
    DashboardTmuxHandlers,
    DashboardUIHandlers
  }

  # Legacy PubSub topics still used for transport (not nervous system signals)
  @pubsub_topics ~w(agent:operator)

  # Events that change filter/search state and need view recompute
  @filter_events ~w(filter clear_filters apply_preset search_feed search_sessions filter_tool filter_tool_use_id clear_events filter_session filter_team filter_agent set_view)

  # UI events that only toggle booleans/state -- no recompute needed
  @ui_no_recompute ~w(toggle_shortcuts_help toggle_create_task_modal toggle_event_detail focus_agent close_agent_focus toggle_add_project set_sub_tab)

  # UI events that change filter state -- need view recompute
  @ui_recompute ~w(keyboard_escape keyboard_navigate add_project)

  # Selection events that just set a selected item -- no data queries
  @selection_no_recompute ~w(select_event select_task select_agent close_detail close_task_detail)

  # select_team needs view recompute (derives sel_team + active_tasks)
  @selection_recompute ~w(select_team)

  @session_control_events ~w(pause_agent resume_agent shutdown_agent hitl_approve hitl_reject kill_switch_click kill_switch_first_confirm kill_switch_second_confirm kill_switch_cancel push_instructions_intent push_instructions_confirm push_instructions_cancel)
  @tmux_events ~w(connect_tmux disconnect_tmux close_all_tmux switch_tmux_tab toggle_tmux_layout send_tmux_keys kill_tmux_session kill_sidebar_tmux launch_session)
  @inspector_events ~w(inspect_team remove_from_inspector close_all_inspector toggle_inspector_layout toggle_maximize_inspector set_inspector_size set_output_mode toggle_agent_output set_message_target send_targeted_message)
  @swarm_events ~w(select_project heal_task reset_all_stale run_health_check reassign_swarm_task claim_swarm_task trigger_gc select_dag_node select_command_agent select_subagent send_command_message clear_command_selection)
  @task_events ~w(create_task update_task_status reassign_task delete_task)
  @note_events ~w(add_note delete_note)
  @feed_events ~w(toggle_session_collapse expand_all collapse_all)
  @fleet_events ~w(toggle_fleet_team set_comms_filter trace_agent clear_trace)
  @p5_events ~w(toggle_agent_grid toggle_entropy_filter select_session toggle_subpanel sort_capability_directory update_route_weight retry_dlq_entry search_archive set_cost_group_by add_policy_rule toggle_forensic_panel toggle_protocol_item)
  @spawn_events ~w(spawn_agent stop_spawned_agent)
  @nav_events ~w(jump_to_timeline jump_to_feed jump_to_agents jump_to_tasks select_timeline_event filter_agent_tasks filter_analytics_tool restore_view_mode)
  @mes_events ~w(mes_pick_up mes_load_subsystem)

  # Messaging events only need view recompute (thread/search state)
  @messaging_view ~w(toggle_thread expand_all_threads collapse_all_threads search_messages)

  @impl true
  def mount(_params, _session, socket) do
    socket = socket |> assign(default_assigns(%{})) |> assign(:recompute_timer, nil)

    if connected?(socket) do
      Enum.each(@pubsub_topics, &Phoenix.PubSub.subscribe(Ichor.PubSub, &1))
      Enum.each(Catalog.categories(), &Ichor.Signals.subscribe/1)
      subscribe_gateway_topics()
      send(self(), :load_data)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    nav_view = parse_nav_view(params["view"])
    socket = assign(socket, :nav_view, nav_view)
    {:noreply, apply_nav_view(nav_view, socket)}
  end

  defp parse_nav_view("fleet"), do: :fleet
  defp parse_nav_view("protocols"), do: :fleet
  defp parse_nav_view("workshop"), do: :workshop
  defp parse_nav_view("signals"), do: :signals
  defp parse_nav_view("mes"), do: :mes
  defp parse_nav_view(_), do: :pipeline

  defp apply_nav_view(:workshop, socket) do
    socket
    |> assign(:ws_blueprints, list_blueprints())
    |> assign(:ws_agent_types, list_agent_types())
    |> push_ws_state()
  end

  defp apply_nav_view(:signals, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ichor.PubSub, "stream:feed")
    end

    assign(socket, :stream_events, Buffer.recent(200))
  end

  defp apply_nav_view(:mes, socket) do
    status =
      try do
        Ichor.Mes.Scheduler.status()
      catch
        :exit, _ -> %{tick: 0, active_runs: 0, next_tick_in: 60_000}
      end

    assign(socket,
      mes_projects: Ichor.Mes.Project.list_all!(),
      mes_scheduler_status: status
    )
  end

  defp apply_nav_view(_nav_view, socket), do: socket

  # ── handle_info ──────────────────────────────────────────────────────

  @impl true
  def handle_info(:load_data, socket) do
    events = Ichor.EventBuffer.latest_per_session()
    socket = socket |> assign(:events, events) |> seed_gateway_assigns() |> recompute()
    subscribe_to_mailboxes(socket.assigns.sessions)
    {:noreply, socket}
  end

  def handle_info({:stream_event, entry}, socket) do
    if socket.assigns.stream_paused do
      {:noreply, socket}
    else
      events = [entry | Enum.take(socket.assigns.stream_events, 499)]
      {:noreply, assign(socket, :stream_events, events)}
    end
  end

  def handle_info(msg, socket), do: DashboardInfoHandlers.dispatch(msg, socket)

  # ── Events: full recompute (data-changing) ───────────────────────────

  @impl true
  def handle_event(e, p, s) when e in @filter_events,
    do: {:noreply, DashboardFilterHandlers.dispatch(e, p, s) |> recompute()}

  def handle_event(e, p, s) when e in @ui_recompute,
    do: {:noreply, DashboardUIHandlers.dispatch(e, p, s) |> recompute()}

  def handle_event(e, p, s) when e in @session_control_events,
    do: {:noreply, DashboardSessionControlHandlers.dispatch(e, p, s) |> recompute()}

  def handle_event(e, p, s) when e in @inspector_events,
    do: {:noreply, DashboardTeamInspectorHandlers.dispatch(e, p, s) |> recompute()}

  def handle_event(e, p, s) when e in @swarm_events,
    do: {:noreply, DashboardSwarmHandlers.dispatch(e, p, s) |> recompute()}

  def handle_event(e, p, s) when e in @task_events,
    do: {:noreply, DashboardTaskHandlers.dispatch(e, p, s) |> recompute()}

  def handle_event(e, p, s) when e in @note_events,
    do: {:noreply, DashboardNotesHandlers.dispatch(e, p, s) |> recompute()}

  def handle_event(e, p, s) when e in @p5_events,
    do: {:noreply, DashboardPhase5Handlers.dispatch(e, p, s) |> recompute()}

  def handle_event(e, p, s) when e in @spawn_events,
    do: {:noreply, DashboardSpawnHandlers.dispatch(e, p, s) |> recompute()}

  def handle_event(e, p, s) when e in @nav_events,
    do: {:noreply, DashboardNavigationHandlers.handle_event(e, p, s) |> recompute()}

  def handle_event(e, p, s) when e in @mes_events,
    do: {:noreply, DashboardMesHandlers.dispatch(e, p, s)}

  # ── Events: view-only recompute (no Ash/SQL queries) ─────────────────

  def handle_event(e, p, s) when e in @selection_recompute,
    do: {:noreply, DashboardSelectionHandlers.dispatch(e, p, s) |> recompute_view()}

  def handle_event(e, p, s) when e in @messaging_view,
    do: {:noreply, DashboardMessagingHandlers.dispatch(e, p, s) |> recompute_view()}

  # ── Events: no recompute (pure UI state) ─────────────────────────────

  def handle_event(e, p, s) when e in @ui_no_recompute,
    do: {:noreply, DashboardUIHandlers.dispatch(e, p, s)}

  def handle_event(e, p, s) when e in @selection_no_recompute,
    do: {:noreply, DashboardSelectionHandlers.dispatch(e, p, s)}

  def handle_event(e, p, s) when e in @tmux_events,
    do: {:noreply, DashboardTmuxHandlers.dispatch(e, p, s)}

  def handle_event(e, p, s) when e in @feed_events,
    do: {:noreply, DashboardFeedHandlers.dispatch(e, p, s)}

  def handle_event(e, p, s) when e in @fleet_events,
    do: {:noreply, DashboardFleetTreeHandlers.dispatch(e, p, s)}

  # ── Events: messaging (passthrough -- handlers return {:noreply, socket}) ──

  def handle_event("send_agent_message", p, s),
    do: DashboardMessagingHandlers.handle_send_agent_message(p, s)

  def handle_event("send_team_broadcast", p, s),
    do: DashboardMessagingHandlers.handle_send_team_broadcast(p, s)

  def handle_event("push_context", p, s), do: DashboardMessagingHandlers.handle_push_context(p, s)

  # ── Events: standalone ─────────────────────────────────────────────────

  def handle_event("toggle_sidebar", _p, s),
    do: {:noreply, DashboardUIHandlers.dispatch("toggle_sidebar", %{}, s)}

  def handle_event("clear_topology_selection", _p, s),
    do: {:noreply, assign(s, :selected_topology_node, nil)}

  def handle_event("restore_state", p, s),
    do: {:noreply, DashboardUIHandlers.handle_restore_state(p, s) |> recompute()}

  # ── Events: archon ─────────────────────────────────────────────────────

  def handle_event("archon_toggle", _p, s),
    do: {:noreply, DashboardArchonHandlers.handle_archon_toggle(s)}

  def handle_event("archon_close", _p, s),
    do: {:noreply, DashboardArchonHandlers.handle_archon_close(s)}

  def handle_event("archon_send", p, s),
    do: {:noreply, DashboardArchonHandlers.handle_archon_send(p, s)}

  def handle_event("archon_shortcode", p, s),
    do: {:noreply, DashboardArchonHandlers.handle_archon_shortcode(p, s)}

  def handle_event("archon_set_tab", %{"tab" => tab}, s),
    do: {:noreply, assign(s, :archon_tab, String.to_existing_atom(tab))}

  def handle_event("dismiss_toast", %{"id" => id}, s),
    do: {:noreply, IchorWeb.DashboardToast.dismiss_toast(s, id)}

  # ── Events: slideout ───────────────────────────────────────────────────

  def handle_event("open_agent_slideout", %{"session_id" => sid}, s),
    do: {:noreply, DashboardSlideoutHandlers.handle_open_agent_slideout(sid, s) |> recompute()}

  def handle_event("close_agent_slideout", _p, s),
    do: {:noreply, DashboardSlideoutHandlers.handle_close_agent_slideout(s)}

  def handle_event("node_selected", %{"trace_id" => tid}, s),
    do: {:noreply, DashboardSlideoutHandlers.handle_node_selected(tid, s)}

  # ── Events: workshop (prefix-match delegation) ─────────────────────────

  def handle_event("ws_edit_type" <> _ = e, p, s),
    do: IchorWeb.WorkshopTypes.handle_event(e, p, s)

  def handle_event("ws_cancel_edit_type" = e, p, s),
    do: IchorWeb.WorkshopTypes.handle_event(e, p, s)

  def handle_event("ws_save_type" = e, p, s), do: IchorWeb.WorkshopTypes.handle_event(e, p, s)
  def handle_event("ws_delete_type" = e, p, s), do: IchorWeb.WorkshopTypes.handle_event(e, p, s)

  def handle_event("ws_save_blueprint" = e, p, s),
    do: IchorWeb.WorkshopPersistence.handle_event(e, p, s)

  def handle_event("ws_load_blueprint" = e, p, s),
    do: IchorWeb.WorkshopPersistence.handle_event(e, p, s)

  def handle_event("ws_delete_blueprint" = e, p, s),
    do: IchorWeb.WorkshopPersistence.handle_event(e, p, s)

  def handle_event("ws_new_blueprint" = e, p, s),
    do: IchorWeb.WorkshopPersistence.handle_event(e, p, s)

  def handle_event("ws_list_blueprints" = e, p, s),
    do: IchorWeb.WorkshopPersistence.handle_event(e, p, s)

  def handle_event("ws_" <> _ = e, p, s),
    do: IchorWeb.DashboardWorkshopHandlers.handle_event(e, p, s)

  # ── Events: signals ────────────────────────────────────────────────

  def handle_event("stream_search", %{"q" => q}, s), do: {:noreply, assign(s, :stream_filter, q)}

  def handle_event("stream_toggle_pause", _p, s),
    do: {:noreply, assign(s, :stream_paused, !s.assigns.stream_paused)}

  def handle_event("stream_clear", _p, s), do: {:noreply, assign(s, :stream_events, [])}

  def handle_event("stream_filter_topic", %{"topic" => t}, s),
    do: {:noreply, assign(s, :stream_filter, t)}

  def handle_event("stop", _p, s), do: {:noreply, s}
end
