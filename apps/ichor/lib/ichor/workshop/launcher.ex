defmodule Ichor.Workshop.Launcher do
  @moduledoc """
  Launches runtime teams from workshop blueprint state.
  """

  alias Ichor.Fleet.Agent
  alias Ichor.Fleet.Team
  alias Ichor.Workshop.Presets

  @spec launch(map()) :: {:ok, map()} | {:error, term()}
  def launch(state) do
    team_name = state.ws_team_name
    cwd = blank_to_nil(state.ws_cwd)

    with {:ok, _} <-
           Team.create_team(team_name, strategy: String.to_existing_atom(state.ws_strategy)) do
      ordered_agents = Presets.spawn_order(state.ws_agents, state.ws_spawn_links)

      launched =
        Enum.count(ordered_agents, fn agent ->
          match?(
            {:ok, _},
            Agent.launch(%{
              name: agent.name,
              capability: agent.capability,
              model: agent.model,
              cwd: cwd,
              team_name: team_name,
              extra_instructions: agent.persona
            })
          )
        end)

      {:ok, %{team_name: team_name, launched: launched, total: length(state.ws_agents)}}
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
