defmodule Ichor.SwarmMonitor.StateBus do
  @moduledoc """
  Signal publication for swarm state updates.
  """

  def broadcast(state) do
    Ichor.Signals.emit(:swarm_state, %{state_map: state})
    Ichor.Signals.emit(:dag_status, %{state_map: state})
  end
end
