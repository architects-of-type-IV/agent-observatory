defmodule Ichor.Dag.Health do
  @moduledoc """
  Health-check boundary for DAG pipelines.
  """

  alias Ichor.Dag.Status
  alias Ichor.SwarmMonitor

  @spec check() :: :ok | {:error, term()}
  def check, do: SwarmMonitor.run_health_check()

  @spec current_report() :: map()
  def current_report, do: Status.health_report()
end
