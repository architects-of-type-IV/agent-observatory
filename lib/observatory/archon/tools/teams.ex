defmodule Observatory.Archon.Tools.Teams do
  @moduledoc """
  Team query tools for Archon. Reads from Fleet.Team code interfaces.
  """
  use Ash.Resource, domain: Observatory.Archon.Tools

  alias Observatory.Fleet.Team, as: FleetTeam

  actions do
    action :list_teams, {:array, :map} do
      description "List all active teams with their members and health status."

      run fn _input, _context ->
        teams =
          FleetTeam.alive!()
          |> Enum.map(fn team ->
            %{
              "name" => team.name,
              "members" => Enum.map(team.members, fn m ->
                %{"session_id" => m[:agent_id] || m[:session_id], "role" => m[:role] || m[:name], "status" => m[:status]}
              end),
              "member_count" => team.member_count,
              "health" => team.health,
              "source" => team.source
            }
          end)

        {:ok, teams}
      end
    end
  end
end
