defmodule Observatory.Fleet.Preparations.LoadTeams do
  @moduledoc """
  Loads team data from hook events and disk state (TeamWatcher).
  Shared preparation for all Fleet.Team read actions.
  """

  use Ash.Resource.Preparation

  import Observatory.Fleet.AgentHealth, only: [compute_agent_health: 2]

  @dead_team_threshold_sec 300

  @impl true
  def prepare(query, _opts, _context) do
    events = Observatory.EventBuffer.list_events()
    disk_teams = Observatory.TeamWatcher.get_state()
    now = DateTime.utc_now()

    teams =
      events
      |> derive_from_events()
      |> merge_with_disk(disk_teams)
      |> Enum.map(&enrich_members(&1, events, now))
      |> mark_dead(now)
      |> Enum.map(&to_resource/1)

    Ash.DataLayer.Simple.set_data(query, teams)
  end

  defp derive_from_events(events) do
    team_creates =
      events
      |> Enum.filter(fn e ->
        e.hook_event_type == :PreToolUse and e.tool_name == "TeamCreate"
      end)
      |> Enum.map(fn e ->
        input = (e.payload || %{})["tool_input"] || %{}
        %{name: input["team_name"], lead_session: e.session_id, created_at: e.inserted_at}
      end)
      |> Enum.reject(fn t -> is_nil(t.name) end)
      |> Enum.uniq_by(& &1.name)

    spawns =
      events
      |> Enum.filter(fn e ->
        e.hook_event_type == :PreToolUse and e.tool_name == "Task" and
          ((e.payload || %{})["tool_input"] || %{})["team_name"] != nil
      end)

    Enum.map(team_creates, fn tc ->
      members =
        spawns
        |> Enum.filter(fn s ->
          ((s.payload || %{})["tool_input"] || %{})["team_name"] == tc.name
        end)
        |> Enum.map(fn s ->
          input = (s.payload || %{})["tool_input"] || %{}
          %{name: input["name"], agent_type: input["subagent_type"], agent_id: nil}
        end)

      %{
        name: tc.name,
        lead_session: tc.lead_session,
        description: nil,
        members: [%{name: "lead", agent_type: "lead", agent_id: tc.lead_session} | members],
        tasks: [],
        source: :events,
        created_at: tc.created_at
      }
    end)
  end

  defp merge_with_disk(event_teams, disk_teams) do
    disk_list =
      disk_teams
      |> Map.values()
      |> Enum.map(fn dt ->
        %{
          name: dt.name,
          lead_session: nil,
          description: dt.description,
          members: dt.members,
          tasks: dt.tasks,
          source: :disk,
          created_at: nil
        }
      end)

    disk_names = MapSet.new(disk_list, & &1.name)
    event_only = Enum.reject(event_teams, fn t -> MapSet.member?(disk_names, t.name) end)
    disk_list ++ event_only
  end

  defp enrich_members(team, events, now) do
    enriched_members =
      Enum.map(team.members, fn m ->
        member_events =
          if m[:agent_id],
            do: Enum.filter(events, &(&1.session_id == m[:agent_id])),
            else: []

        latest =
          member_events
          |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
          |> List.first()

        status =
          cond do
            latest == nil -> :unknown
            latest.hook_event_type == :SessionEnd -> :ended
            DateTime.diff(now, latest.inserted_at, :second) > 30 -> :idle
            true -> :active
          end

        health_data = compute_agent_health(member_events, now)
        model = extract_model(member_events)
        cwd = extract_cwd(member_events)

        first_event = Enum.min_by(member_events, & &1.inserted_at, DateTime, fn -> nil end)
        uptime = if first_event, do: DateTime.diff(now, first_event.inserted_at, :second), else: nil

        Map.merge(m, %{
          event_count: length(member_events),
          latest_event: latest,
          status: status,
          health: health_data.health,
          health_issues: health_data.issues,
          failure_rate: health_data.failure_rate,
          model: model,
          cwd: cwd,
          uptime: uptime
        })
      end)

    %{team | members: enriched_members}
  end

  defp mark_dead(teams, now) do
    Enum.map(teams, fn team ->
      if team.source == :disk do
        Map.put(team, :dead?, false)
      else
        latest_member_event =
          team.members
          |> Enum.map(& &1[:latest_event])
          |> Enum.reject(&is_nil/1)
          |> Enum.max_by(& &1.inserted_at, DateTime, fn -> nil end)

        all_inactive? =
          Enum.all?(team.members, fn m ->
            m[:status] in [:ended, :idle, :unknown, nil]
          end)

        stale? =
          case latest_member_event do
            nil -> true
            event -> DateTime.diff(now, event.inserted_at, :second) > @dead_team_threshold_sec
          end

        Map.put(team, :dead?, all_inactive? and stale?)
      end
    end)
  end

  defp to_resource(team) do
    healths = Enum.map(team.members, & &1[:health])

    health =
      cond do
        :critical in healths -> :critical
        :warning in healths -> :warning
        :healthy in healths -> :healthy
        true -> :unknown
      end

    struct!(Observatory.Fleet.Team, %{
      name: team.name,
      lead_session: team[:lead_session],
      description: team[:description],
      members: team.members,
      tasks: team[:tasks] || [],
      source: team.source,
      created_at: team[:created_at],
      dead?: team[:dead?] || false,
      member_count: length(team.members),
      health: health
    })
  end

  defp extract_model(events) do
    session_start = Enum.find(events, &(&1.hook_event_type == :SessionStart))

    if session_start do
      (session_start.payload || %{})["model"] || session_start.model_name
    else
      Enum.find_value(events, fn e -> e.model_name || (e.payload || %{})["model"] end)
    end
  end

  defp extract_cwd(events) do
    events
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.find_value(fn e -> e.cwd end)
  end
end
