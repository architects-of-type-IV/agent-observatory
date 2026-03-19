defmodule Ichor.Projects.Status do
  @moduledoc """
  Public runtime status boundary for DAG pipelines.

  This preserves the current pipeline-state shape while moving the
  status API under `Ichor.Dag`, where the autonomous pipeline runtime
  belongs.
  """

  alias Ichor.Projects.Runtime

  @spec state() :: map()
  def state, do: Runtime.state()

  @spec set_active_project(String.t()) :: :ok | {:error, term()}
  def set_active_project(project_key), do: Runtime.set_active_project(project_key)

  @spec add_project(String.t(), String.t()) :: :ok | {:error, term()}
  def add_project(key, path), do: Runtime.add_project(key, path)

  @spec health_report() :: map()
  def health_report do
    state()
    |> Map.get(:health, %{})
  end
end
