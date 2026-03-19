defmodule Ichor.Dag.StateBusTest do
  use ExUnit.Case, async: true

  alias Ichor.Dag.StateBus
  alias Ichor.Signals
  alias Ichor.Signals.Message

  test "broadcast publishes dag_status updates" do
    Signals.subscribe(:dag)

    state = %{tasks: [%{id: "t-1"}], pipeline: %{total: 1}}

    StateBus.broadcast(state)

    assert_receive %Message{name: :dag_status, data: %{state_map: ^state}}
  end
end
