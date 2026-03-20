defmodule IchorWeb.DashboardState do
  @moduledoc """
  Recomputes derived dashboard assigns using Ash domain resources.
  Two tiers: `recompute/1` (full data + view) and `recompute_view/1` (display-only, no queries).
  """

  import Phoenix.Component, only: [assign: 3]
  import IchorWeb.DashboardDataHelpers, only: [filtered_events: 1, filtered_sessions: 2]
  import IchorWeb.DashboardTeamHelpers, only: [all_team_sids: 1]
  import IchorWeb.DashboardFeedHelpers, only: [build_feed_groups: 2]

  alias Ichor.Factory.PipelineMonitor
  alias Ichor.Infrastructure.HITLRelay
  alias Ichor.Infrastructure.Tmux
  alias Ichor.Infrastructure.TmuxDiscovery
  alias Ichor.Notes
  alias Ichor.Signals.Bus
  alias Ichor.Signals.TaskProjection
  alias Ichor.Signals.ToolFailure
  alias Ichor.Workshop.ActiveTeam
  alias Ichor.Workshop.Agent
  alias Ichor.Workshop.Analysis.Queries, as: FQ
  alias Ichor.Workshop.Analysis.SessionEviction

  def default_assigns(disk_teams) do
    %{
      events: [],
      filter_source_app: nil,
      filter_session_id: nil,
      filter_event_type: nil,
      filter_slow: false,
      search_feed: "",
      search_sessions: "",
      search_history: [],
      selected_event: nil,
      selected_task: nil,
      selected_agent: nil,
      expanded_events: [],
      now: DateTime.utc_now(),
      page_title: "ICHOR IV",
      view_mode: :command,
      activity_tab: :comms,
      pipeline_tab: :board,
      agent_slideout: nil,
      slideout_terminal: "",
      slideout_activity: [],
      expanded_sessions: MapSet.new(),
      disk_teams: disk_teams,
      pipeline_state: runtime_state(),
      protocol_stats: %{},
      selected_pipeline_task: nil,
      selected_command_agent: nil,
      show_add_project: false,
      selected_team: nil,
      selected_message_target: nil,
      show_shortcuts_help: false,
      collapsed_fleet_teams: MapSet.new(),
      comms_team_filter: nil,
      comms_agent_filter: [],
      sidebar_collapsed: false,
      active_tmux_session: nil,
      tmux_output: "",
      tmux_sessions: [],
      tmux_panels: [],
      tmux_outputs: %{},
      tmux_layout: :tabs,
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
      ws_team_id: nil,
      ws_teams: [],
      ws_agent_types: [],
      ws_editing_type: nil,
      # Toast notifications
      toasts: [],
      # Archon overlay
      show_archon: false,
      archon_tab: :command,
      archon_messages: [],
      archon_history: [],
      archon_loading: false,
      archon_snapshot: %{},
      archon_attention: [],
      # Recompute-derived assigns (defaults for static render before :load_data)
      teams: [],
      has_teams: false,
      sessions: [],
      total_sessions: 0,
      messages: [],
      active_tasks: [],
      errors: [],
      error_groups: [],
      visible_events: [],
      event_notes: [],
      feed_groups: [],
      sel_team: nil,
      nav_view: :pipeline,
      # Stream view
      stream_filter: "",
      stream_paused: false,
      # MES
      mes_projects: [],
      mes_scheduler_status: %{tick: 0, active_runs: 0, next_tick_in: 60_000, paused: false},
      planning_project: nil,
      gate_report: nil,
      planning_sub_tab: :decisions,
      planning_selected: nil,
      selected_mes_project: nil
    }
  end

  @doc "Full recompute: queries all Ash domains + derives view assigns."
  def recompute(socket) do
    do_recompute(socket)
  rescue
    ArgumentError -> socket
  end

  defp runtime_state do
    PipelineMonitor.state()
  catch
    :exit, _ -> %{}
  end

  defp do_recompute(socket) do
    assigns = socket.assigns

    # Evict events from stale sessions (no activity in TTL)
    events = SessionEviction.evict_stale(assigns.events, assigns.now)
    socket = assign(socket, :events, events)
    assigns = socket.assigns

    # Ash domain queries
    teams = ActiveTeam.alive!()
    all_teams = ActiveTeam.all!()
    agents = Agent.all!()
    event_tasks = TaskProjection.current!() |> Enum.map(&task_to_map/1)
    errors = ToolFailure.recent!()
    error_groups = ToolFailure.by_tool!()

    # Session derivation (Fleet.Queries)
    all_sessions =
      FQ.active_sessions(assigns.events, tmux: assigns[:tmux_sessions] || [], now: assigns.now)

    tmux_only = FQ.active_sessions([], tmux: assigns[:tmux_sessions] || [], now: assigns.now)
    team_sids = all_team_sids(all_teams)

    standalone =
      all_sessions
      |> Enum.reject(fn s ->
        MapSet.member?(team_sids, s.session_id) or infrastructure_entry?(s)
      end)

    event_notes = Notes.list_notes()

    # Auto-select team when only 1 exists
    selected_team = resolve_selected_team(assigns.selected_team, teams)
    sel_team = find_team(teams, selected_team)

    active_tasks =
      cond do
        sel_team && sel_team.tasks != [] -> sel_team.tasks
        event_tasks != [] -> event_tasks
        true -> []
      end

    # Tmux session list (for sidebar)
    tmux_session_names = safe_tmux_sessions()
    teams = merge_display_teams(teams, agents, tmux_session_names)

    # Unified agent index from Fleet.Agent
    agent_index = build_agent_lookup(agents)

    # Template-layer data
    paused_sessions = safe_paused_sessions()

    mailbox_messages =
      Bus.recent_messages(50)
      |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
      |> Enum.take(50)

    # Conditional: only compute expensive derivations for active view
    feed_groups = maybe_feed(assigns, teams, tmux_only)

    socket
    |> assign(:agent_index, agent_index)
    |> assign(:visible_events, filtered_events(assigns))
    |> assign(:feed_groups, feed_groups)
    |> assign(:sessions, filtered_sessions(standalone, assigns.search_sessions))
    |> assign(:total_sessions, length(all_sessions))
    |> assign(:teams, teams)
    |> assign(:has_teams, teams != [])
    |> assign(:active_tasks, active_tasks)
    |> assign(:messages, mailbox_messages)
    |> assign(:event_notes, event_notes)
    |> assign(:selected_team, selected_team)
    |> assign(:sel_team, sel_team)
    |> assign(:errors, errors)
    |> assign(:error_groups, error_groups)
    |> assign(:paused_sessions, paused_sessions)
    |> assign(:mailbox_messages, mailbox_messages)
    |> assign(:tmux_sessions, tmux_session_names)
  end

  @doc "View-only recompute: re-derives display assigns from existing data. No Ash/SQL queries."
  def recompute_view(socket) do
    assigns = socket.assigns
    teams = assigns[:teams] || []

    selected_team = resolve_selected_team(assigns.selected_team, teams)
    sel_team = find_team(teams, selected_team)

    active_tasks =
      cond do
        sel_team && sel_team.tasks != [] -> sel_team.tasks
        (assigns[:active_tasks] || []) != [] -> assigns.active_tasks
        true -> []
      end

    socket
    |> assign(:visible_events, filtered_events(assigns))
    |> assign(:selected_team, selected_team)
    |> assign(:sel_team, sel_team)
    |> assign(:active_tasks, active_tasks)
  end

  defp safe_paused_sessions do
    HITLRelay.paused_sessions() |> MapSet.new()
  rescue
    _ -> MapSet.new()
  end

  defp safe_tmux_sessions do
    Tmux.list_sessions()
  rescue
    _ -> []
  end

  # Feed groups needed on command/activity views with feed/comms tab
  defp maybe_feed(assigns, teams, tmux_only) do
    if assigns.view_mode == :command and assigns.activity_tab in [:feed, :comms] do
      groups = build_feed_groups(assigns.events, teams)
      groups ++ Enum.map(tmux_only, &tmux_feed_entry(&1, assigns.now))
    else
      assigns[:feed_groups] || []
    end
  end

  defp infrastructure_entry?(%{session_id: sid}) do
    sid == "operator" or TmuxDiscovery.infrastructure_session?(sid)
  end

  defp task_to_map(%{id: _id} = t), do: Map.from_struct(t)
  defp task_to_map(t) when is_map(t), do: t

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

  defp resolve_selected_team(current, _teams) when not is_nil(current), do: current
  defp resolve_selected_team(nil, [team]), do: team.name
  defp resolve_selected_team(nil, _teams), do: nil

  defp find_team(_teams, nil), do: nil

  defp find_team(teams, name) when is_binary(name) do
    Enum.find(teams, &(&1.name == name))
  end

  defp merge_display_teams(teams, agents, tmux_sessions) do
    existing_names = MapSet.new(teams, & &1.name)

    discovered =
      tmux_sessions
      |> Enum.reject(fn s ->
        TmuxDiscovery.infrastructure_session?(s) or MapSet.member?(existing_names, s)
      end)
      |> Enum.map(fn session_name ->
        members =
          agents
          |> Enum.filter(&agent_in_tmux_session?(&1, session_name))
          |> Enum.map(&agent_to_team_member/1)

        %{
          name: session_name,
          lead_session: nil,
          description: "Discovered from tmux session",
          members: members,
          tasks: [],
          source: :beam,
          created_at: nil,
          dead?: false,
          member_count: length(members),
          health: inferred_team_health(members)
        }
      end)
      |> Enum.reject(&(&1.members == []))

    teams ++ discovered
  end

  defp build_agent_lookup(agents) do
    agents
    |> Enum.flat_map(fn agent ->
      agent_map =
        agent
        |> Map.from_struct()
        |> Map.merge(%{
          team: agent.team_name,
          project: agent.cwd && Path.basename(agent.cwd),
          tmux_session: get_in(agent.channels || %{}, [:tmux]) || agent.tmux_session
        })

      [agent.agent_id, agent.session_id, agent.short_name]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(&{&1, agent_map})
    end)
    |> dedup_by_status()
  end

  defp agent_in_tmux_session?(agent, session_name) do
    (get_in(agent.channels || %{}, [:tmux]) || agent.tmux_session) == session_name
  end

  defp agent_to_team_member(agent) do
    %{
      name: agent.short_name || agent.name || agent.agent_id,
      agent_id: agent.agent_id,
      agent_type: to_string(agent.role || :worker),
      status: agent.status,
      health: agent.health || :unknown,
      model: agent.model,
      cwd: agent.cwd
    }
  end

  defp inferred_team_health(members) do
    healths = Enum.map(members, &Map.get(&1, :health, :unknown))

    cond do
      :critical in healths -> :critical
      :warning in healths -> :warning
      :healthy in healths -> :healthy
      true -> :unknown
    end
  end

  defp dedup_by_status(pairs) do
    Enum.reduce(pairs, %{}, fn {key, entry}, acc ->
      case Map.get(acc, key) do
        %{status: :active} -> acc
        _ -> Map.put(acc, key, entry)
      end
    end)
  end
end
