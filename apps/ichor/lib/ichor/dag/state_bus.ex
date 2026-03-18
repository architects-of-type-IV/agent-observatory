defmodule Ichor.Dag.StateBus do
  @moduledoc """
  Signal publication for DAG runtime state updates.
  """

  def broadcast(state) do
    Ichor.Signals.emit(:dag_status, %{state_map: state})
  end
end
