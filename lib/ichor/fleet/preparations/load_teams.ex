defmodule Ichor.Fleet.Preparations.LoadTeams do
  @moduledoc """
  Loads team data from hook events and disk state (TeamWatcher).
  Shared preparation for all Fleet.Team read actions.
  """

  use Ash.Resource.Preparation

  import Ichor.Fleet.AgentHealth, only: [compute_agent_health: 2]

  alias Ash.DataLayer.Simple
  alias Ichor.EventBuffer
  alias Ichor.Fleet.AgentProcess
  alias Ichor.Fleet.Team
  alias Ichor.Fleet.TeamSupervisor
  alias Ichor.Gateway.AgentRegistry

  @dead_team_threshold_sec 300

  @impl true
  def prepare(query, _opts, _context) do
    events = EventBuffer.list_events()
    now = DateTime.utc_now()

    registry_by_id =
      AgentRegistry.list_all()
      |> AgentRegistry.build_lookup()

    events_by_session = Enum.group_by(events, & &1.session_id)

    teams =
      events
      |> derive_from_events()
      |> merge_with_beam_teams()
      |> Enum.map(&enrich_members(&1, events_by_session, now, registry_by_id))
      |> mark_dead(now)
      |> Enum.map(&to_resource/1)

    Simple.set_data(query, teams)
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

  # Merge BEAM-native teams (from TeamSupervisor/FleetSupervisor) with legacy sources
  defp merge_with_beam_teams(existing_teams) do
    beam_teams = TeamSupervisor.list_all()
    existing_names = MapSet.new(existing_teams, & &1.name)

    new_teams =
      beam_teams
      |> Enum.reject(fn {name, _meta} -> MapSet.member?(existing_names, name) end)
      |> Enum.map(fn {name, meta} ->
        member_ids = TeamSupervisor.member_ids(name)

        members =
          Enum.map(member_ids, fn id ->
            case AgentProcess.lookup(id) do
              {_pid, agent_meta} ->
                %{
                  name: id,
                  agent_id: id,
                  agent_type: to_string(agent_meta[:role] || :worker),
                  status: agent_meta[:status] || :active
                }

              nil ->
                %{name: id, agent_id: id, agent_type: "worker"}
            end
          end)

        %{
          name: name,
          lead_session: nil,
          description: nil,
          members: members,
          tasks: [],
          source: :beam,
          created_at: nil,
          project: meta[:project]
        }
      end)

    existing_teams ++ new_teams
  end

  defp enrich_members(team, events_by_session, now, registry_by_id) do
    enriched_members =
      Enum.map(team.members, fn m ->
        # Find registry entry for this member (correlates short names with UUIDs)
        reg = Map.get(registry_by_id, m[:agent_id])
        event_sid = if(reg, do: reg.session_id, else: m[:agent_id])

        member_events = Map.get(events_by_session, event_sid, [])

        latest =
          member_events
          |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
          |> List.first()

        # Registry is authoritative for status; fall back to event-derived
        status =
          cond do
            reg != nil -> reg.status
            latest == nil -> :unknown
            latest.hook_event_type == :SessionEnd -> :ended
            DateTime.diff(now, latest.inserted_at, :second) > 30 -> :idle
            true -> :active
          end

        health_data = compute_agent_health(member_events, now)
        model = extract_model(member_events) || m[:model]
        cwd = extract_cwd(member_events) || m[:cwd]

        first_event = Enum.min_by(member_events, & &1.inserted_at, DateTime, fn -> nil end)

        uptime =
          if first_event, do: DateTime.diff(now, first_event.inserted_at, :second), else: nil

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
      if team.source == :beam do
        # BEAM-supervised teams are never marked dead by staleness
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

    struct!(Team, %{
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
