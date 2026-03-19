defmodule Ichor.Fleet.RuntimeView do
  @moduledoc """
  Shared runtime projections for team and agent display state.
  """

  alias Ichor.Gateway.TmuxDiscovery

  def resolve_selected_team(current, _teams) when not is_nil(current), do: current
  def resolve_selected_team(nil, [team]), do: team.name
  def resolve_selected_team(nil, _teams), do: nil

  def find_team(_teams, nil), do: nil

  def find_team(teams, name) when is_binary(name) do
    Enum.find(teams, &(&1.name == name))
  end

  def merge_display_teams(teams, agents, tmux_sessions) do
    existing_names = MapSet.new(teams, & &1.name)

    discovered =
      tmux_sessions
      |> Enum.reject(&TmuxDiscovery.infrastructure_session?/1)
      |> Enum.reject(&MapSet.member?(existing_names, &1))
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

  def build_agent_lookup(agents) do
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
