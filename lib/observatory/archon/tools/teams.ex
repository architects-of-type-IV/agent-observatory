defmodule Observatory.Archon.Tools.Teams do
  @moduledoc """
  Team query tools for Archon.
  """
  use Ash.Resource, domain: Observatory.Archon.Tools

  alias Observatory.TeamWatcher

  actions do
    action :list_teams, {:array, :map} do
      description "List all active teams with their members and health status."

      run fn _input, _context ->
        teams =
          TeamWatcher.get_state()
          |> Enum.map(fn {name, team} ->
            %{
              "name" => name,
              "members" => Enum.map(team.members, fn m ->
                %{"session_id" => m.session_id, "role" => m[:role], "status" => m[:status]}
              end),
              "member_count" => length(team.members),
              "source" => team[:source]
            }
          end)

        {:ok, teams}
      end
    end
  end
end
