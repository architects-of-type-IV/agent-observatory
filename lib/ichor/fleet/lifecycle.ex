defmodule Ichor.Fleet.Lifecycle do
  @moduledoc """
  Public boundary for team runtime lifecycle operations.
  """

  alias Ichor.Fleet.Lifecycle.TeamLaunch
  alias Ichor.Fleet.Lifecycle.TeamSpec

  @doc "Launch a multi-agent team from a TeamSpec."
  @spec launch_team(TeamSpec.t()) :: {:ok, String.t()} | {:error, term()}
  defdelegate launch_team(spec), to: TeamLaunch, as: :launch
end
