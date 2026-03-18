defmodule Ichor.SwarmMonitor.StateBusTest do
  use ExUnit.Case, async: true

  alias Ichor.Signals
  alias Ichor.Signals.Message
  alias Ichor.SwarmMonitor.StateBus

  test "broadcast emits both legacy and dag-native status signals" do
    Signals.subscribe(:swarm_state)
    Signals.subscribe(:dag_status)

    state = %{tasks: [%{id: "t-1"}], active_project: "alpha"}

    StateBus.broadcast(state)

    assert_receive %Message{name: :swarm_state, data: %{state_map: ^state}}
    assert_receive %Message{name: :dag_status, data: %{state_map: ^state}}
  end
end
