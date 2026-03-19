defmodule IchorWeb.DashboardTeamHelpers do
  @moduledoc """
  Team derivation and management helpers for the Ichor Dashboard.
  Handles merging event-based teams with disk-persisted teams.
  """

  alias Ichor.Gateway.AgentRegistry.AgentEntry

  @doc """
  Derive teams from both events and disk state, merging them appropriately.
  Disk teams are authoritative when available.
  """
  def derive_teams(events, disk_teams) do
    event_teams = derive_teams_from_events(events)
    merge_team_sources(event_teams, disk_teams)
  end

  defp derive_teams_from_events(events) do
    team_creates = extract_team_creates(events)
    spawns = extract_spawns(events)
    Enum.map(team_creates, &build_event_team(&1, spawns))
  end

  defp extract_team_creates(events) do
    events
    |> Enum.filter(fn e -> e.hook_event_type == :PreToolUse and e.tool_name == "TeamCreate" end)
    |> Enum.map(fn e ->
      input = (e.payload || %{})["tool_input"] || %{}
      %{name: input["team_name"], lead_session: e.session_id, created_at: e.inserted_at}
    end)
    |> Enum.reject(fn t -> is_nil(t.name) end)
    |> Enum.uniq_by(& &1.name)
  end

  defp extract_spawns(events) do
    Enum.filter(events, fn e ->
      e.hook_event_type == :PreToolUse and e.tool_name == "Task" and
        ((e.payload || %{})["tool_input"] || %{})["team_name"] != nil
    end)
  end

  defp build_event_team(tc, spawns) do
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
  Detect whether a team member is a lead or regular member.
  Delegates agent_type classification to AgentEntry.role_from_string/1.
  """
  def detect_role(team, member) do
    case AgentEntry.role_from_string(member[:agent_type]) do
      role when role in [:lead, :coordinator] ->
        :lead

      _ ->
        if team.lead_session != nil and member[:agent_id] == team.lead_session,
          do: :lead,
          else: :member
    end
  end
end
