defmodule IchorWeb.DashboardLive do
  @moduledoc """
  Root LiveView for the Ichor dashboard.

  Orchestrates all dashboard panels — pipeline, fleet, signals, MES, workshop.
  Event routing is delegated to focused handler modules (DashboardInfoHandlers,
  DashboardMesHandlers, etc.). Navigation state is driven by URL params.
  """

  use IchorWeb, :live_view

  import IchorWeb.DashboardDataHelpers, only: [unique_values: 2]
  import IchorWeb.DashboardFormatHelpers, only: [build_export_url: 4]
  import IchorWeb.DashboardAgentHelpers, only: [agent_tasks: 2]
  import IchorWeb.DashboardAgentActivityHelpers, only: [agent_events: 2]
  import IchorWeb.DashboardState, only: [recompute: 1, recompute_view: 1, default_assigns: 1]

  import IchorWeb.DashboardWorkshopHandlers,
    only: [list_teams: 0, list_agent_types: 0, push_ws_state: 1]

  import IchorWeb.DashboardMessagingHandlers, only: [subscribe_to_mailboxes: 1]
  import IchorWeb.Components.Primitives.AgentInfoList
  import IchorWeb.Components.Primitives.NavIcon
  import IchorWeb.Components.Primitives.AgentActions
  import IchorWeb.Components.Primitives.CloseButton
  import IchorWeb.Components.Primitives.PanelHeader

  alias Ichor.Factory.Project
  alias Ichor.Infrastructure.AnsiUtils
  alias Ichor.Projector.SignalBuffer, as: Buffer
  alias Ichor.Signals.{Catalog, Message}
  alias Ichor.Signals.EventStream, as: EventRuntime

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
    DashboardPipelineHandlers,
    DashboardSelectionHandlers,
    DashboardSessionControlHandlers,
    DashboardSettingsHandlers,
    DashboardSlideoutHandlers,
    DashboardSpawnHandlers,
    DashboardTaskHandlers,
    DashboardTmuxHandlers,
    DashboardUIHandlers
  }

  @archon_positions %{
    "center" => :center,
    "bottom" => :bottom,
    "top" => :top,
    "left" => :left,
    "right" => :right
  }

  # Events that change filter/search state and need view recompute
  @filter_events ~w(filter clear_filters apply_preset search_feed search_sessions filter_tool filter_tool_use_id clear_events filter_session filter_team filter_agent set_view)

  # UI events that only toggle booleans/state -- no recompute needed
  @ui_no_recompute ~w(toggle_shortcuts_help toggle_event_detail focus_agent close_agent_focus toggle_add_project set_sub_tab)

  # UI events that change filter state -- need view recompute
  @ui_recompute ~w(keyboard_escape keyboard_navigate add_project)

  # Selection events that just set a selected item -- no data queries
  @selection_no_recompute ~w(select_event select_task select_agent close_detail close_task_detail)

  # select_team needs view recompute (derives sel_team + active_tasks)
  @selection_recompute ~w(select_team)

  @session_control_events ~w(pause_agent resume_agent shutdown_agent hitl_approve hitl_reject kill_switch_click kill_switch_first_confirm kill_switch_second_confirm kill_switch_cancel push_instructions_intent push_instructions_confirm push_instructions_cancel)
  @tmux_events ~w(connect_tmux connect_tmux_split connect_all_windows disconnect_tmux disconnect_tmux_tab close_all_tmux switch_tmux_tab toggle_tmux_layout send_tmux_keys kill_tmux_session kill_sidebar_tmux launch_session toggle_terminal_panel close_terminal_panel cycle_panel_position set_panel_position set_panel_width set_panel_height set_panel_split set_panel_theme set_panel_layout terminal_panel_init terminal_panel_resize terminal_resized toggle_session_picker toggle_panel_settings)
  @pipeline_events ~w(select_pipeline_project heal_pipeline_task heal_task reset_pipeline_stale run_pipeline_health_check reassign_pipeline_task claim_pipeline_task trigger_pipeline_gc select_pipeline_task select_command_agent send_command_message clear_command_selection)
  @task_events ~w(update_task_status reassign_task delete_task)
  @note_events ~w(add_note delete_note)
  @feed_events ~w(toggle_session_collapse expand_all collapse_all)
  @fleet_events ~w(toggle_fleet_team set_comms_filter trace_agent clear_trace)
  @spawn_events ~w(spawn_agent stop_spawned_agent)
  @nav_events ~w(jump_to_agents restore_view_mode)
  @mes_events ~w(mes_pick_up mes_load_plugin toggle_mes_scheduler mes_select_project mes_deselect_project mes_start_mode mes_gate_check mes_generate_dag mes_launch_dag planning_switch_tab planning_select_artifact planning_close_reader)
  @messaging_events ~w(set_message_target send_targeted_message)
  @settings_events ~w(settings_project_event select_settings_category)

  # Messaging events only need view recompute (thread/search state)
  @impl true
  def mount(_params, _session, socket) do
    socket = socket |> assign(default_assigns(%{})) |> assign(:recompute_timer, nil)

    if connected?(socket) do
      Enum.each(Catalog.categories(), &Ichor.Signals.subscribe/1)

      # ADR-026: subscribe to signal activation topics
      for signal_mod <- Application.get_env(:ichor, :signal_modules, []) do
        Phoenix.PubSub.subscribe(Ichor.PubSub, "signal:#{signal_mod.signal_name()}")
      end

      send(self(), :load_data)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    nav_view = parse_nav_view(params["view"])

    socket =
      socket
      |> assign(:nav_view, nav_view)
      |> assign(:settings_category, parse_settings_category(params["category"]))

    socket = apply_nav_view(nav_view, socket)

    {:noreply, socket}
  end

  defp parse_settings_category("projects"), do: :projects
  defp parse_settings_category(_), do: :projects

  defp parse_nav_view("fleet"), do: :fleet
  defp parse_nav_view("protocols"), do: :fleet
  defp parse_nav_view("workshop"), do: :workshop
  defp parse_nav_view("signals"), do: :signals
  defp parse_nav_view("mes"), do: :mes
  defp parse_nav_view("settings"), do: :settings
  defp parse_nav_view(_), do: :pipeline

  defp apply_nav_view(:workshop, socket) do
    socket
    |> assign(:ws_teams, list_teams())
    |> assign(:ws_agent_types, list_agent_types())
    |> push_ws_state()
  end

  defp apply_nav_view(:signals, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ichor.PubSub, "signals:feed")
    end

    socket =
      case socket.assigns do
        %{streams: %{signals: _}} -> socket
        _ -> stream_configure(socket, :signals, dom_id: fn {seq, _msg} -> "signal-#{seq}" end)
      end

    stream(socket, :signals, Buffer.recent(200), reset: true)
  end

  defp apply_nav_view(:mes, socket) do
    assign(socket,
      mes_projects: Project.list_all!(),
      mes_scheduler_status: DashboardMesHandlers.fetch_scheduler_status(),
      selected_mes_project: nil,
      planning_project: nil,
      gate_report: nil
    )
  end

  defp apply_nav_view(:settings, socket) do
    assign(socket, :settings_projects, Ichor.Settings.list_settings_projects!())
  end

  defp apply_nav_view(_nav_view, socket), do: socket

  @impl true
  def handle_info(:load_data, socket) do
    events = EventRuntime.latest_per_session()
    socket = socket |> assign(:events, events) |> recompute()
    subscribe_to_mailboxes(socket.assigns.sessions)
    {:noreply, socket}
  end

  def handle_info({:signal, seq, %Message{} = message}, socket) do
    cond do
      socket.assigns.stream_paused ->
        {:noreply, socket}

      not passes_filter?(message, socket.assigns.stream_filter) ->
        {:noreply, socket}

      not Map.has_key?(socket.assigns[:streams] || %{}, :signals) ->
        {:noreply, socket}

      true ->
        {:noreply, stream_insert(socket, :signals, {seq, message}, at: 0, limit: 200)}
    end
  end

  def handle_info({:signal_activated, %Ichor.Signals.Signal{} = signal}, socket),
    do: DashboardInfoHandlers.dispatch({:signal_activated, signal}, socket)

  def handle_info(msg, socket), do: DashboardInfoHandlers.dispatch(msg, socket)

  @impl true
  def handle_event(e, p, s) when e in @filter_events,
    do: {:noreply, DashboardFilterHandlers.dispatch(e, p, s) |> recompute()}

  def handle_event(e, p, s) when e in @ui_recompute,
    do: {:noreply, DashboardUIHandlers.dispatch(e, p, s) |> recompute()}

  def handle_event(e, p, s) when e in @session_control_events,
    do: {:noreply, DashboardSessionControlHandlers.dispatch(e, p, s) |> recompute()}

  def handle_event(e, p, s) when e in @pipeline_events,
    do: {:noreply, DashboardPipelineHandlers.dispatch(e, p, s) |> recompute()}

  def handle_event(e, p, s) when e in @task_events,
    do: {:noreply, DashboardTaskHandlers.dispatch(e, p, s) |> recompute()}

  def handle_event(e, p, s) when e in @note_events,
    do: {:noreply, DashboardNotesHandlers.dispatch(e, p, s) |> recompute()}

  def handle_event(e, p, s) when e in @spawn_events,
    do: {:noreply, DashboardSpawnHandlers.dispatch(e, p, s) |> recompute()}

  def handle_event(e, p, s) when e in @nav_events,
    do: {:noreply, DashboardNavigationHandlers.handle_event(e, p, s) |> recompute()}

  def handle_event(e, p, s) when e in @mes_events,
    do: {:noreply, DashboardMesHandlers.dispatch(e, p, s)}

  def handle_event(e, p, s) when e in @selection_recompute,
    do: {:noreply, DashboardSelectionHandlers.dispatch(e, p, s) |> recompute_view()}

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

  def handle_event(e, p, s) when e in @messaging_events,
    do: {:noreply, DashboardMessagingHandlers.dispatch(e, p, s)}

  def handle_event(e, p, s) when e in @settings_events,
    do: {:noreply, DashboardSettingsHandlers.dispatch(e, p, s)}

  def handle_event("send_agent_message", p, s),
    do: DashboardMessagingHandlers.handle_send_agent_message(p, s)

  def handle_event("send_team_broadcast", p, s),
    do: DashboardMessagingHandlers.handle_send_team_broadcast(p, s)

  def handle_event("push_context", p, s), do: DashboardMessagingHandlers.handle_push_context(p, s)

  def handle_event("toggle_sidebar", _p, s),
    do: {:noreply, DashboardUIHandlers.dispatch("toggle_sidebar", %{}, s)}

  def handle_event("restore_state", p, s),
    do: {:noreply, DashboardUIHandlers.handle_restore_state(p, s) |> recompute()}

  def handle_event("archon_toggle", _p, s),
    do: {:noreply, DashboardArchonHandlers.handle_archon_toggle(s)}

  def handle_event("archon_close", _p, s),
    do: {:noreply, DashboardArchonHandlers.handle_archon_close(s)}

  def handle_event("archon_send", p, s),
    do: {:noreply, DashboardArchonHandlers.handle_archon_send(p, s)}

  def handle_event("archon_shortcode", p, s),
    do: {:noreply, DashboardArchonHandlers.handle_archon_shortcode(p, s)}

  @archon_tab_map %{"command" => :command, "chat" => :chat, "ref" => :ref}

  def handle_event("archon_set_tab", %{"tab" => tab}, s) do
    case Map.fetch(@archon_tab_map, tab) do
      {:ok, tab_atom} ->
        {:noreply,
         s
         |> assign(:archon_tab, tab_atom)
         |> DashboardArchonHandlers.refresh_manager_state()}

      :error ->
        {:noreply, s}
    end
  end

  def handle_event("archon_toggle_settings", _p, s),
    do: {:noreply, assign(s, :show_archon_settings, !s.assigns.show_archon_settings)}

  def handle_event("archon_set_position", %{"position" => pos}, s) do
    position = archon_parse_position(pos)

    {:noreply,
     s
     |> assign(:archon_position, position)
     |> Phoenix.LiveView.push_event("archon_panel_update", %{position: pos})}
  end

  def handle_event("archon_set_size", %{"size" => size}, s) do
    parsed = max(25, min(100, String.to_integer(size)))

    {:noreply,
     s
     |> assign(:archon_size, parsed)
     |> Phoenix.LiveView.push_event("archon_panel_update", %{size: parsed})}
  end

  def handle_event("archon_panel_init", params, s) do
    {:noreply,
     assign(s,
       archon_position: archon_parse_position(params["position"]),
       archon_size:
         max(25, min(100, (params["size"] || 75) |> to_string() |> String.to_integer()))
     )}
  end

  def handle_event("dismiss_toast", %{"id" => id}, s),
    do: {:noreply, IchorWeb.DashboardToast.dismiss_toast(s, id)}

  def handle_event("open_agent_slideout", %{"session_id" => sid}, s),
    do: {:noreply, DashboardSlideoutHandlers.handle_open_agent_slideout(sid, s) |> recompute()}

  def handle_event("close_agent_slideout", _p, s),
    do: {:noreply, DashboardSlideoutHandlers.handle_close_agent_slideout(s)}

  def handle_event("ws_edit_type" <> _ = e, p, s),
    do: IchorWeb.WorkshopTypes.handle_event(e, p, s)

  def handle_event("ws_cancel_edit_type" = e, p, s),
    do: IchorWeb.WorkshopTypes.handle_event(e, p, s)

  def handle_event("ws_save_type" = e, p, s), do: IchorWeb.WorkshopTypes.handle_event(e, p, s)
  def handle_event("ws_delete_type" = e, p, s), do: IchorWeb.WorkshopTypes.handle_event(e, p, s)

  def handle_event("ws_save_team" = e, p, s),
    do: IchorWeb.WorkshopPersistence.handle_event(e, p, s)

  def handle_event("ws_load_team" = e, p, s),
    do: IchorWeb.WorkshopPersistence.handle_event(e, p, s)

  def handle_event("ws_delete_team" = e, p, s),
    do: IchorWeb.WorkshopPersistence.handle_event(e, p, s)

  def handle_event("ws_new_team" = e, p, s),
    do: IchorWeb.WorkshopPersistence.handle_event(e, p, s)

  def handle_event("ws_list_teams" = e, p, s),
    do: IchorWeb.WorkshopPersistence.handle_event(e, p, s)

  def handle_event("ws_" <> _ = e, p, s),
    do: IchorWeb.DashboardWorkshopHandlers.handle_event(e, p, s)

  def handle_event("stream_search", %{"q" => q}, s) do
    s = assign(s, :stream_filter, q)
    {:noreply, stream(s, :signals, filtered_signals(q), reset: true)}
  end

  def handle_event("stream_toggle_pause", _p, s),
    do: {:noreply, assign(s, :stream_paused, !s.assigns.stream_paused)}

  def handle_event("stream_clear", _p, s),
    do: {:noreply, assign(s, :stream_filter, "") |> stream(:signals, [], reset: true)}

  def handle_event("stream_filter_topic", %{"topic" => t}, s) do
    s = assign(s, :stream_filter, t)
    {:noreply, stream(s, :signals, filtered_signals(t), reset: true)}
  end

  def handle_event("stop", _p, s), do: {:noreply, s}

  defp filtered_signals(""), do: Buffer.recent(200)

  defp filtered_signals(filter) do
    f = String.downcase(filter)
    Buffer.recent(200) |> Enum.filter(&signal_matches?(&1, f))
  end

  defp passes_filter?(_message, ""), do: true

  defp passes_filter?(%Message{domain: domain, name: name}, filter) do
    f = String.downcase(filter)

    String.contains?(Atom.to_string(domain), f) or
      String.contains?(Atom.to_string(name), f) or
      String.contains?("#{domain}:#{name}", f)
  end

  defp signal_matches?({_seq, %Message{domain: domain, name: name}}, f) do
    String.contains?(Atom.to_string(domain), f) or
      String.contains?(Atom.to_string(name), f) or
      String.contains?("#{domain}:#{name}", f)
  end

  defp archon_parse_position(pos), do: Map.get(@archon_positions, to_string(pos), :center)
end
