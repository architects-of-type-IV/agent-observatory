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
      |> assign(:now, DateTime.utc_now())
      |> assign(:page_title, "Observatory")
      |> assign(:view_mode, :overview)
      |> assign(:disk_teams, disk_teams)
      |> assign(:selected_team, nil)
      |> assign(:mailbox_counts, %{})
      |> assign(:collapsed_threads, %{})
      |> assign(:show_shortcuts_help, false)
      |> assign(:show_create_task_modal, false)
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
  def handle_event("filter", params, socket) do
    {:noreply, handle_filter(params, socket) |> prepare_assigns()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, handle_clear_filters(socket) |> prepare_assigns()}
  end

  def handle_event("apply_preset", %{"preset" => preset}, socket) do
    {:noreply, handle_apply_preset(preset, socket) |> prepare_assigns()}
  end

  def handle_event("search_feed", %{"q" => q}, socket) do
    {:noreply, handle_search_feed(q, socket) |> prepare_assigns()}
  end

  def handle_event("search_sessions", %{"q" => q}, socket) do
    {:noreply, handle_search_sessions(q, socket) |> prepare_assigns()}
  end

  def handle_event("select_event", %{"id" => id}, socket) do
    cur = socket.assigns.selected_event
    selected = if cur && cur.id == id, do: nil, else: Enum.find(socket.assigns.events, &(&1.id == id))
    {:noreply, socket |> assign(:selected_event, selected) |> assign(:selected_task, nil) |> prepare_assigns()}
  end

  def handle_event("close_detail", p, socket), do: {:noreply, handle_close_detail(p, socket) |> prepare_assigns()}

  def handle_event("select_task", %{"id" => id}, socket) do
    cur = socket.assigns.selected_task
    selected = if cur && cur[:id] == id, do: nil, else: Enum.find(socket.assigns.active_tasks, &(&1[:id] == id))
    {:noreply, socket |> assign(:selected_task, selected) |> assign(:selected_event, nil) |> prepare_assigns()}
  end

  def handle_event("close_task_detail", p, socket), do: {:noreply, handle_close_task_detail(p, socket) |> prepare_assigns()}

  def handle_event("filter_tool", %{"tool" => tool}, socket) do
    {:noreply, handle_filter_tool(tool, socket) |> prepare_assigns()}
  end

  def handle_event("filter_tool_use_id", %{"tuid" => tuid}, socket) do
    {:noreply, handle_filter_tool_use_id(tuid, socket) |> prepare_assigns()}
  end

  def handle_event("clear_events", _params, socket) do
    {:noreply, socket |> assign(:events, []) |> prepare_assigns()}
  end

  def handle_event("filter_session", %{"sid" => sid}, socket) do
    {:noreply, handle_filter_session(sid, socket) |> prepare_assigns()}
  end

  def handle_event("set_view", %{"mode" => mode}, socket) do
    {:noreply, handle_set_view(mode, socket) |> prepare_assigns()}
  end

  def handle_event("restore_state", params, socket) do
    {:noreply, handle_restore_state(params, socket) |> prepare_assigns()}
  end

  def handle_event("select_team", %{"name" => name}, socket) do
    selected = if socket.assigns.selected_team == name, do: nil, else: name
    {:noreply, socket |> assign(:selected_team, selected) |> prepare_assigns()}
  end

  def handle_event("filter_team", %{"name" => name}, socket) do
    {:noreply, handle_filter_team(name, socket) |> prepare_assigns()}
  end

  def handle_event("filter_agent", %{"session_id" => sid}, socket) do
    {:noreply, handle_filter_agent(sid, socket) |> prepare_assigns()}
  end

  def handle_event("send_agent_message", params, socket) do
    handle_send_agent_message(params, socket)
  end

  def handle_event("send_team_broadcast", params, socket) do
    handle_send_team_broadcast(params, socket)
  end

  def handle_event("push_context", params, socket) do
    handle_push_context(params, socket)
  end

  def handle_event("toggle_shortcuts_help", params, socket) do
    {:noreply, handle_toggle_shortcuts_help(params, socket) |> prepare_assigns()}
  end

  def handle_event("toggle_create_task_modal", params, socket) do
    {:noreply, handle_toggle_create_task_modal(params, socket) |> prepare_assigns()}
  end

  def handle_event("create_task", params, socket) do
    result = handle_create_task(params, socket)

    case result do
      {:noreply, updated_socket} ->
        {:noreply, updated_socket |> assign(:show_create_task_modal, false) |> prepare_assigns()}
      other ->
        other
    end
  end

  def handle_event("keyboard_escape", params, socket) do
    {:noreply, handle_keyboard_escape(params, socket) |> prepare_assigns()}
  end

  def handle_event("keyboard_navigate", params, socket) do
    {:noreply, handle_keyboard_navigate(params, socket) |> prepare_assigns()}
  end

  def handle_event("add_note", params, socket) do
    {:noreply, result_socket} = handle_add_note(params, socket)
    {:noreply, result_socket |> prepare_assigns()}
  end

  def handle_event("delete_note", params, socket) do
    {:noreply, result_socket} = handle_delete_note(params, socket)
    {:noreply, result_socket |> prepare_assigns()}
  end

  def handle_event("search_messages", params, socket) do
    {:noreply, handle_search_messages(params, socket) |> prepare_assigns()}
  end

  def handle_event("toggle_thread", params, socket) do
    {:noreply, handle_toggle_thread(params, socket) |> prepare_assigns()}
  end

  def handle_event("expand_all_threads", _params, socket) do
    {:noreply, handle_expand_all_threads(socket) |> prepare_assigns()}
  end

  def handle_event("collapse_all_threads", _params, socket) do
    {:noreply, handle_collapse_all_threads(socket) |> prepare_assigns()}
  end

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

  defp prepare_assigns(socket) do
    assigns = socket.assigns
    all_sessions = active_sessions(assigns.events)
    teams = derive_teams(assigns.events, assigns.disk_teams)
    teams = Enum.map(teams, &enrich_team_members(&1, assigns.events, assigns.now))
    team_sids = all_team_sids(teams)
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

    socket
    |> assign(:visible_events, filtered_events(assigns))
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
