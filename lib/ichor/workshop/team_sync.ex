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
    existing =
      TeamMember
      |> Ash.Query.for_read(:for_team, %{team_id: team.id})
      |> Ash.read!()

    Enum.each(existing, &Ash.destroy!/1)

    state
    |> Map.get(:ws_agents, [])
    |> Enum.with_index()
    |> Enum.each(fn {agent, index} ->
      TeamMember
      |> Ash.Changeset.for_create(:create, %{
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
      })
      |> Ash.create!()
    end)

    :ok
  rescue
    error -> {:error, error}
  end
end
