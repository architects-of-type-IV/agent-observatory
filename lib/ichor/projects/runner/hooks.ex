defmodule Ichor.Projects.Runner.Hooks do
  @moduledoc """
  Cleanup policy dispatcher.

  Routes cleanup requests to the correct implementation based on the
  policy declared in a `Runner.Mode` cleanup config.
  """

  alias Ichor.Control.Lifecycle.TeamLaunch
  alias Ichor.Projects.Runner.Hooks.MES

  @doc "Executes the cleanup policy for a run."
  @spec cleanup(atom(), struct()) :: :ok
  def cleanup(:mes_janitor, state) do
    MES.cleanup(state)
  end

  def cleanup(:teardown, %{team_spec: nil}), do: :ok

  def cleanup(:teardown, state) do
    TeamLaunch.teardown(state.team_spec)
    :ok
  end
end
