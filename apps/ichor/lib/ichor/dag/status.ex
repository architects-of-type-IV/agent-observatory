defmodule Ichor.Dag.Status do
  @moduledoc """
  Public runtime status boundary for DAG pipelines.

  This preserves the current pipeline-state shape while moving the
  status API under `Ichor.Dag`, where the autonomous pipeline runtime
  belongs.
  """

  alias Ichor.SwarmMonitor

  @spec state() :: map()
  def state, do: SwarmMonitor.get_state()

  @spec set_active_project(String.t()) :: :ok | {:error, term()}
  def set_active_project(project_key), do: SwarmMonitor.set_active_project(project_key)

  @spec add_project(String.t(), String.t()) :: :ok | {:error, term()}
  def add_project(key, path), do: SwarmMonitor.add_project(key, path)

  @spec health_report() :: map()
  def health_report do
    state()
    |> Map.get(:health, %{})
  end

  @spec projects() :: map()
  def projects do
    state()
    |> Map.get(:watched_projects, %{})
  end

  @spec active_project() :: String.t() | nil
  def active_project do
    state()
    |> Map.get(:active_project)
  end
end
