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

    socket
    |> assign(:visible_events, filtered_events(assigns))
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
