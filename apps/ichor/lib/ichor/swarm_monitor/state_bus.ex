defmodule Ichor.SwarmMonitor.StateBus do
  @moduledoc """
  Compatibility wrapper for DAG runtime state publication.
  """

  defdelegate broadcast(state), to: Ichor.Dag.StateBus
end
