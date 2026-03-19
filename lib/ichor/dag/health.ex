defmodule Ichor.Dag.Health do
  @moduledoc """
  Health-check boundary for DAG pipelines.
  """

  alias Ichor.Dag.Runtime

  @spec check() :: :ok | {:error, term()}
  def check, do: Runtime.run_health_check()
end
