defmodule Ichor.Archon.Tools.Teams do
  @moduledoc """
  Team query tools for Archon. Reads from Fleet.Team code interfaces.
  """
  use Ash.Resource, domain: Ichor.Archon.Tools

  alias Ichor.Fleet
  alias Ichor.Fleet.RuntimeQuery

  actions do
    action :list_teams, {:array, :map} do
      description("List all active teams with their members and health status.")

      run(fn _input, _context ->
        teams =
          Fleet.list_alive_teams()
          |> Enum.map(&RuntimeQuery.format_team/1)

        {:ok, teams}
      end)
    end
  end
end
