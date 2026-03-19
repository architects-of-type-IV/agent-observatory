defmodule Ichor.Dag.GC do
  @moduledoc """
  Garbage-collection boundary for DAG pipeline archives and cleanup.
  """

  alias Ichor.Dag.Runtime

  @spec trigger(String.t()) :: :ok | {:error, term()}
  def trigger(team_name), do: Runtime.trigger_gc(team_name)
end
