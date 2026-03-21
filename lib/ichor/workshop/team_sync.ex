defmodule Ichor.Workshop.TeamSync do
  @moduledoc """
  Orchestrates bulk synchronisation of persisted TeamMember records from
  Workshop canvas state.  Replaces all existing members for a team with the
  current set derived from the in-memory canvas.
  """

  alias Ichor.Workshop.{Team, TeamMember}

  @doc "Replace all persisted members for a team from Workshop state."
  @spec sync_from_workshop_state(Team.t(), map()) :: :ok | {:error, term()}
  def sync_from_workshop_state(%Team{} = team, state) do
    query = Ash.Query.for_read(TeamMember, :for_team, %{team_id: team.id})

    with {:ok, existing} <- Ash.read(query),
         :ok <- destroy_all(existing) do
      create_members(team, Map.get(state, :ws_agents, []))
    end
  end

  defp destroy_all(members) do
    Enum.reduce_while(members, :ok, fn member, :ok ->
      case Ash.destroy(member) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp create_members(team, agents) do
    agents
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {agent, index}, :ok ->
      attrs = %{
        team_id: team.id,
        agent_type_id: agent[:agent_type_id],
        slot: agent.id,
        position: index,
        name: agent.name,
        capability: agent.capability,
        model: agent.model,
        permission: agent.permission,
        extra_instructions: agent.persona || "",
        file_scope: agent.file_scope || "",
        quality_gates: agent.quality_gates || "",
        tool_scope: Map.get(agent, :tools, []),
        canvas_x: agent.x,
        canvas_y: agent.y
      }

      case TeamMember |> Ash.Changeset.for_create(:create, attrs) |> Ash.create() do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
