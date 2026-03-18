defmodule Ichor.Workshop.Launcher do
  @moduledoc """
  Launches runtime teams from workshop blueprint state.
  """

  alias Ichor.Fleet.Lifecycle
  alias Ichor.Workshop.TeamSpecBuilder

  @spec launch(map()) :: {:ok, map()} | {:error, term()}
  def launch(state) do
    spec = TeamSpecBuilder.build_from_state(state)

    with {:ok, session} <- Lifecycle.launch_team(spec) do
      {:ok,
       %{
         team_name: spec.team_name,
         session: session,
         launched: length(spec.agents),
         total: length(spec.agents)
       }}
    end
  end
end
