defmodule ObservatoryWeb.DashboardLive do
  use ObservatoryWeb, :live_view
  import ObservatoryWeb.DashboardTeamHelpers
  import ObservatoryWeb.DashboardDataHelpers
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.DashboardMessagingHandlers
  import ObservatoryWeb.DashboardTaskHandlers
  import ObservatoryWeb.DashboardTimelineHelpers
  import ObservatoryWeb.DashboardSessionHelpers
  import ObservatoryWeb.DashboardUIHandlers
  import ObservatoryWeb.DashboardNotificationHandlers
  import ObservatoryWeb.DashboardFilterHandlers
  import ObservatoryWeb.DashboardMessageHelpers
  import ObservatoryWeb.DashboardNotesHandlers
  import ObservatoryWeb.DashboardAgentHelpers
  import ObservatoryWeb.DashboardAgentActivityHelpers
  import ObservatoryWeb.DashboardFeedHelpers

  @max_events 500

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "events:stream")
      Phoenix.PubSub.subscribe(Observatory.PubSub, "teams:update")
      Phoenix.PubSub.subscribe(Observatory.PubSub, "agent:crashes")
      :timer.send_interval(1000, self(), :tick)
    end

    events = load_recent_events()
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
      |> assign(:view_mode, :overview)
      |> assign(:disk_teams, disk_teams)
      |> assign(:selected_team, nil)
      |> assign(:mailbox_counts, %{})
      |> assign(:collapsed_threads, %{})
      |> assign(:show_shortcuts_help, false)
      |> assign(:show_create_task_modal, false)
      |> assign(:feed_grouped, false)
      |> prepare_assigns()

    # Subscribe to mailbox channels for all active sessions
    if connected?(socket) do
      subscribe_to_mailboxes(socket.assigns.sessions)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info({:new_event, event}, socket) do
    events = [event | socket.assigns.events] |> Enum.take(@max_events)
    {:noreply, socket |> assign(:events, events) |> prepare_assigns()}
  end

  def handle_info(:tick, socket) do
    {:noreply, socket |> assign(:now, DateTime.utc_now()) |> prepare_assigns()}
  end

  def handle_info({:teams_updated, teams}, socket) do
    {:noreply, socket |> assign(:disk_teams, teams) |> prepare_assigns()}
  end

  def handle_info({:new_mailbox_message, message}, socket) do
    handle_new_mailbox_message(message, socket)
  end

  def handle_info({:agent_crashed, session_id, team_name, reassigned_count}, socket) do
    {:noreply, handle_agent_crashed(session_id, team_name, reassigned_count, socket) |> prepare_assigns()}
  end

  @impl true
  def handle_event("filter", p, s), do: {:noreply, handle_filter(p, s) |> prepare_assigns()}
  def handle_event("clear_filters", _p, s), do: {:noreply, handle_clear_filters(s) |> prepare_assigns()}
  def handle_event("apply_preset", %{"preset" => preset}, s), do: {:noreply, handle_apply_preset(preset, s) |> prepare_assigns()}
  def handle_event("search_feed", %{"q" => q}, s), do: {:noreply, handle_search_feed(q, s) |> prepare_assigns()}
  def handle_event("search_sessions", %{"q" => q}, s), do: {:noreply, handle_search_sessions(q, s) |> prepare_assigns()}

  def handle_event("select_event", %{"id" => id}, socket) do
    cur = socket.assigns.selected_event
    sel = if cur && cur.id == id, do: nil, else: Enum.find(socket.assigns.events, &(&1.id == id))
    {:noreply, socket |> clear_selections() |> assign(:selected_event, sel) |> prepare_assigns()}
  end

  def handle_event("select_task", %{"id" => id}, socket) do
    cur = socket.assigns.selected_task
    sel = if cur && cur[:id] == id, do: nil, else: Enum.find(socket.assigns.active_tasks, &(&1[:id] == id))
    {:noreply, socket |> clear_selections() |> assign(:selected_task, sel) |> prepare_assigns()}
  end

  def handle_event("select_agent", %{"id" => id}, socket) do
    cur = socket.assigns.selected_agent
    sel = if cur && cur[:agent_id] == id, do: nil, else: find_agent_by_id(socket.assigns.teams, id)
    {:noreply, socket |> clear_selections() |> assign(:selected_agent, sel) |> prepare_assigns()}
  end

  def handle_event(e, p, s) when e in ["close_detail", "close_task_detail"] do
    h = if e == "close_detail", do: handle_close_detail(p, s), else: handle_close_task_detail(p, s)
    {:noreply, h |> prepare_assigns()}
  end

  def handle_event("filter_tool", %{"tool" => t}, s), do: {:noreply, handle_filter_tool(t, s) |> prepare_assigns()}
  def handle_event("filter_tool_use_id", %{"tuid" => t}, s), do: {:noreply, handle_filter_tool_use_id(t, s) |> prepare_assigns()}
  def handle_event("clear_events", _p, s), do: {:noreply, s |> assign(:events, []) |> prepare_assigns()}
  def handle_event("filter_session", %{"sid" => sid}, s), do: {:noreply, handle_filter_session(sid, s) |> prepare_assigns()}
  def handle_event("set_view", %{"mode" => m}, s), do: {:noreply, handle_set_view(m, s) |> prepare_assigns()}
  def handle_event("restore_state", p, s), do: {:noreply, handle_restore_state(p, s) |> prepare_assigns()}

  def handle_event("select_team", %{"name" => name}, s) do
    sel = if s.assigns.selected_team == name, do: nil, else: name
    {:noreply, s |> assign(:selected_team, sel) |> prepare_assigns()}
  end

  def handle_event("filter_team", %{"name" => n}, s), do: {:noreply, handle_filter_team(n, s) |> prepare_assigns()}
  def handle_event("filter_agent", %{"session_id" => sid}, s), do: {:noreply, handle_filter_agent(sid, s) |> prepare_assigns()}
  def handle_event("send_agent_message", p, s), do: handle_send_agent_message(p, s)
  def handle_event("send_team_broadcast", p, s), do: handle_send_team_broadcast(p, s)
  def handle_event("push_context", p, s), do: handle_push_context(p, s)
  def handle_event("toggle_shortcuts_help", p, s), do: {:noreply, handle_toggle_shortcuts_help(p, s) |> prepare_assigns()}
  def handle_event("toggle_create_task_modal", p, s), do: {:noreply, handle_toggle_create_task_modal(p, s) |> prepare_assigns()}
  def handle_event("toggle_event_detail", p, s), do: {:noreply, handle_toggle_event_detail(p, s) |> prepare_assigns()}
  def handle_event("focus_agent", p, s), do: {:noreply, handle_focus_agent(p, s) |> prepare_assigns()}
  def handle_event("close_agent_focus", p, s), do: {:noreply, handle_close_agent_focus(p, s) |> prepare_assigns()}
  def handle_event("toggle_feed_grouping", _p, s), do: {:noreply, s |> assign(:feed_grouped, !s.assigns.feed_grouped) |> prepare_assigns()}
  def handle_event("pause_agent", p, s), do: {:noreply, ObservatoryWeb.DashboardSessionControlHandlers.handle_pause_agent(p, s) |> prepare_assigns()}
  def handle_event("resume_agent", p, s), do: {:noreply, ObservatoryWeb.DashboardSessionControlHandlers.handle_resume_agent(p, s) |> prepare_assigns()}
  def handle_event("shutdown_agent", p, s), do: {:noreply, ObservatoryWeb.DashboardSessionControlHandlers.handle_shutdown_agent(p, s) |> prepare_assigns()}

  def handle_event("create_task", p, s) do
    case handle_create_task(p, s) do
      {:noreply, upd} -> {:noreply, upd |> assign(:show_create_task_modal, false) |> prepare_assigns()}
      other -> other
    end
  end

  def handle_event("update_task_status", p, s) do
    case handle_update_task_status(p, s) do
      {:noreply, upd} -> {:noreply, upd |> prepare_assigns()}
      other -> other
    end
  end

  def handle_event("reassign_task", p, s) do
    case handle_reassign_task(p, s) do
      {:noreply, upd} -> {:noreply, upd |> prepare_assigns()}
      other -> other
    end
  end

  def handle_event("delete_task", p, s) do
    case handle_delete_task(p, s) do
      {:noreply, upd} -> {:noreply, upd |> prepare_assigns()}
      other -> other
    end
  end

  def handle_event("keyboard_escape", p, s), do: {:noreply, handle_keyboard_escape(p, s) |> prepare_assigns()}
  def handle_event("keyboard_navigate", p, s), do: {:noreply, handle_keyboard_navigate(p, s) |> prepare_assigns()}

  def handle_event("add_note", p, s) do
    {:noreply, res} = handle_add_note(p, s)
    {:noreply, res |> prepare_assigns()}
  end

  def handle_event("delete_note", p, s) do
    {:noreply, res} = handle_delete_note(p, s)
    {:noreply, res |> prepare_assigns()}
  end

  def handle_event("search_messages", p, s), do: {:noreply, handle_search_messages(p, s) |> prepare_assigns()}
  def handle_event("toggle_thread", p, s), do: {:noreply, handle_toggle_thread(p, s) |> prepare_assigns()}
  def handle_event("expand_all_threads", _p, s), do: {:noreply, handle_expand_all_threads(s) |> prepare_assigns()}
  def handle_event("collapse_all_threads", _p, s), do: {:noreply, handle_collapse_all_threads(s) |> prepare_assigns()}

  # Navigation handlers
  def handle_event(e, p, s) when e in ["jump_to_timeline", "jump_to_feed", "jump_to_agents", "jump_to_tasks", "select_timeline_event", "filter_agent_tasks", "filter_analytics_tool"] do
    ObservatoryWeb.DashboardNavigationHandlers.handle_event(e, p, s) |> then(&{:noreply, prepare_assigns(&1)})
  end


  defp load_recent_events do
    case Ash.read(Observatory.Events.Event, action: :read) do
      {:ok, events} ->
        events
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
        |> Enum.take(@max_events)

      _ ->
        []
    end
  end

  defp find_agent_by_id(teams, agent_id) do
    teams |> Enum.flat_map(& &1.members) |> Enum.find(&(&1[:agent_id] == agent_id))
  end

  defp clear_selections(socket) do
    socket |> assign(:selected_event, nil) |> assign(:selected_task, nil) |> assign(:selected_agent, nil)
  end

  defp prepare_assigns(socket) do
    assigns = socket.assigns
    all_sessions = active_sessions(assigns.events)
    all_teams = derive_teams(assigns.events, assigns.disk_teams)
    all_teams = Enum.map(all_teams, &enrich_team_members(&1, assigns.events, assigns.now))
    all_teams = detect_dead_teams(all_teams, assigns.now)
    teams = Enum.reject(all_teams, & &1[:dead?])
    team_sids = all_team_sids(all_teams)
    standalone = Enum.reject(all_sessions, fn s -> MapSet.member?(team_sids, s.session_id) end)

    event_tasks = derive_tasks(assigns.events)
    messages = derive_messages(assigns.events)
    filtered_messages = search_messages(messages, assigns.search_messages)
    message_threads = group_messages_by_thread(filtered_messages)

    event_notes = Observatory.Notes.list_notes()

    # For the selected team, merge disk tasks with event tasks
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

    has_teams? = teams != []

    # Compute error and analytics data
    errors = extract_errors(assigns.events)
    error_groups = group_errors(errors)
    analytics = compute_tool_analytics(assigns.events)
    timeline = compute_timeline_data(assigns.events)

    feed_groups = if assigns[:feed_grouped], do: build_feed_groups(assigns.events, assigns), else: []

    socket
    |> assign(:visible_events, filtered_events(assigns))
    |> assign(:feed_groups, feed_groups)
    |> assign(:sessions, filtered_sessions(standalone, assigns.search_sessions))
    |> assign(:total_sessions, length(all_sessions))
    |> assign(:teams, teams)
    |> assign(:has_teams, has_teams?)
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
  end
end
