defmodule ObservatoryWeb.DashboardTeamHelpers do
  @moduledoc """
  Team derivation and management helpers for the Observatory Dashboard.
  Handles merging event-based teams with disk-persisted teams.
  """

  import ObservatoryWeb.DashboardAgentHealthHelpers

  @doc """
  Derive teams from both events and disk state, merging them appropriately.
  Disk teams are authoritative when available.
  """
  def derive_teams(events, disk_teams) do
    event_teams = derive_teams_from_events(events)
    merge_team_sources(event_teams, disk_teams)
  end

  defp derive_teams_from_events(events) do
    # Find TeamCreate events
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

    # Find teammate spawn events (Task tool with team_name)
    spawns =
      events
      |> Enum.filter(fn e ->
        e.hook_event_type == :PreToolUse and e.tool_name == "Task" and
          ((e.payload || %{})["tool_input"] || %{})["team_name"] != nil
      end)

    # Build team structs
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

  defp merge_team_sources(event_teams, disk_teams) do
    # Disk teams are authoritative when available
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

    # Merge: disk data wins for teams that exist in both
    disk_names = MapSet.new(disk_list, & &1.name)

    event_only =
      Enum.reject(event_teams, fn t -> MapSet.member?(disk_names, t.name) end)

    disk_list ++ event_only
  end

  @doc """
  Extract session IDs from team members.
  """
  def team_member_sids(team) do
    team.members
    |> Enum.map(& &1[:agent_id])
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Get all session IDs across all teams.
  """
  def all_team_sids(teams) do
    teams
    |> Enum.flat_map(&team_member_sids/1)
    |> MapSet.new()
  end

  @doc """
  Enrich team members with event-based status and activity data.
  """
  def enrich_team_members(team, events, now) do
    Map.update!(team, :members, fn members ->
      Enum.map(members, fn m ->
        member_events =
          if m[:agent_id] do
            Enum.filter(events, &(&1.session_id == m[:agent_id]))
          else
            []
          end

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

        # Compute health metrics
        health_data = compute_agent_health(member_events, now)

        Map.merge(m, %{
          event_count: length(member_events),
          latest_event: latest,
          status: status,
          health: health_data.health,
          health_issues: health_data.issues,
          failure_rate: health_data.failure_rate
        })
      end)
    end)
  end

  @doc """
  Get color class for member status indicator (now health-based).
  """
  def member_status_color(member) when is_map(member) do
    health_color(member[:health] || :unknown)
  end

  def member_status_color(:active), do: "bg-emerald-500"
  def member_status_color(:idle), do: "bg-amber-500"
  def member_status_color(:ended), do: "bg-zinc-600"
  def member_status_color(_), do: "bg-zinc-700"
end
