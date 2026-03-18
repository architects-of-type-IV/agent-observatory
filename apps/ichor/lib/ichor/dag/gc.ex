defmodule Ichor.Dag.GC do
  @moduledoc """
  Garbage-collection boundary for DAG pipeline archives and cleanup.
  """

  alias Ichor.SwarmMonitor

  @spec trigger(String.t()) :: :ok | {:error, term()}
  def trigger(team_name), do: SwarmMonitor.trigger_gc(team_name)
end
