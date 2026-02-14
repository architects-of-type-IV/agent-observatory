defmodule ObservatoryWeb.DashboardLive do
  use ObservatoryWeb, :live_view
  import ObservatoryWeb.DashboardTeamHelpers
  import ObservatoryWeb.DashboardDataHelpers
  import ObservatoryWeb.DashboardFormatHelpers

  @max_events 500

  # ═══════════════════════════════════════════════════════
  # Mount + Lifecycle
  # ═══════════════════════════════════════════════════════

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "events:stream")
      Phoenix.PubSub.subscribe(Observatory.PubSub, "teams:update")
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
      |> assign(:search_feed, "")
      |> assign(:search_sessions, "")
      |> assign(:selected_event, nil)
      |> assign(:selected_task, nil)
      |> assign(:now, DateTime.utc_now())
      |> assign(:page_title, "Observatory")
      |> assign(:view_mode, :feed)
      |> assign(:disk_teams, disk_teams)
      |> assign(:selected_team, nil)
      |> prepare_assigns()

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

  # ═══════════════════════════════════════════════════════
  # Event Handlers
  # ═══════════════════════════════════════════════════════

  @impl true
  def handle_event("filter", params, socket) do
    socket =
      socket
      |> assign(:filter_source_app, blank_to_nil(params["source_app"]))
      |> assign(:filter_session_id, blank_to_nil(params["session_id"]))
      |> assign(:filter_event_type, blank_to_nil(params["event_type"]))
      |> prepare_assigns()

    {:noreply, socket}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:filter_source_app, nil)
     |> assign(:filter_session_id, nil)
     |> assign(:filter_event_type, nil)
     |> assign(:search_feed, "")
     |> assign(:search_sessions, "")
     |> prepare_assigns()}
  end

  def handle_event("search_feed", %{"q" => q}, socket) do
    {:noreply, socket |> assign(:search_feed, q) |> prepare_assigns()}
  end

  def handle_event("search_sessions", %{"q" => q}, socket) do
    {:noreply, socket |> assign(:search_sessions, q) |> prepare_assigns()}
  end

  def handle_event("select_event", %{"id" => id}, socket) do
    selected =
      if socket.assigns.selected_event && socket.assigns.selected_event.id == id do
        nil
      else
        Enum.find(socket.assigns.events, &(&1.id == id))
      end

    {:noreply, socket |> assign(:selected_event, selected) |> assign(:selected_task, nil) |> prepare_assigns()}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, socket |> assign(:selected_event, nil) |> prepare_assigns()}
  end

  def handle_event("select_task", %{"id" => id}, socket) do
    selected =
      if socket.assigns.selected_task && socket.assigns.selected_task[:id] == id do
        nil
      else
        Enum.find(socket.assigns.active_tasks, &(&1[:id] == id))
      end

    {:noreply, socket |> assign(:selected_task, selected) |> assign(:selected_event, nil) |> prepare_assigns()}
  end

  def handle_event("close_task_detail", _params, socket) do
    {:noreply, socket |> assign(:selected_task, nil) |> prepare_assigns()}
  end

  def handle_event("filter_tool", %{"tool" => tool}, socket) do
    {:noreply, socket |> assign(:search_feed, tool) |> prepare_assigns()}
  end

  def handle_event("filter_tool_use_id", %{"tuid" => tuid}, socket) do
    {:noreply, socket |> assign(:search_feed, tuid) |> prepare_assigns()}
  end

  def handle_event("clear_events", _params, socket) do
    {:noreply, socket |> assign(:events, []) |> prepare_assigns()}
  end

  def handle_event("filter_session", %{"sid" => sid}, socket) do
    {:noreply, socket |> assign(:filter_session_id, sid) |> prepare_assigns()}
  end

  def handle_event("set_view", %{"mode" => mode}, socket) do
    {:noreply, socket |> assign(:view_mode, String.to_existing_atom(mode)) |> prepare_assigns()}
  end

  def handle_event("select_team", %{"name" => name}, socket) do
    selected = if socket.assigns.selected_team == name, do: nil, else: name
    {:noreply, socket |> assign(:selected_team, selected) |> prepare_assigns()}
  end

  def handle_event("filter_team", %{"name" => name}, socket) do
    # Filter feed to only show events from this team's sessions
    team = Enum.find(derive_teams(socket.assigns.events, socket.assigns.disk_teams), &(&1.name == name))

    if team do
      sids = team_member_sids(team)
      # Use the first session ID for filtering (or clear if multiple)
      case sids do
        [sid] -> {:noreply, socket |> assign(:filter_session_id, sid) |> prepare_assigns()}
        _ -> {:noreply, socket |> assign(:search_feed, name) |> prepare_assigns()}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("filter_agent", %{"session_id" => sid}, socket) do
    {:noreply, socket |> assign(:filter_session_id, sid) |> assign(:view_mode, :feed) |> prepare_assigns()}
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

  # ═══════════════════════════════════════════════════════
  # Assign Preparation for Template
  # ═══════════════════════════════════════════════════════

  defp prepare_assigns(socket) do
    assigns = socket.assigns
    all_sessions = active_sessions(assigns.events)
    teams = derive_teams(assigns.events, assigns.disk_teams)
    teams = Enum.map(teams, &enrich_team_members(&1, assigns.events, assigns.now))
    team_sids = all_team_sids(teams)
    standalone = Enum.reject(all_sessions, fn s -> MapSet.member?(team_sids, s.session_id) end)

    # Derive event-based task and message state
    event_tasks = derive_tasks(assigns.events)
    messages = derive_messages(assigns.events)

    # For the selected team, merge disk tasks with event tasks
    sel_team = Enum.find(teams, fn t -> t.name == assigns.selected_team end)

    active_tasks =
      cond do
        sel_team && sel_team.tasks != [] -> sel_team.tasks
        event_tasks != [] -> event_tasks
        true -> []
      end

    has_teams? = teams != []

    socket
    |> assign(:visible_events, filtered_events(assigns))
    |> assign(:sessions, filtered_sessions(standalone, assigns.search_sessions))
    |> assign(:total_sessions, length(all_sessions))
    |> assign(:teams, teams)
    |> assign(:has_teams, has_teams?)
    |> assign(:active_tasks, active_tasks)
    |> assign(:messages, messages)
    |> assign(:sel_team, sel_team)
  end
end
