defmodule Ichor.Workshop.PresetsTest do
  use ExUnit.Case, async: true

  alias Ichor.Workshop.{BlueprintState, Presets}

  test "apply loads a known preset into state" do
    state = Presets.apply(BlueprintState.defaults(), "solo")

    assert state.ws_team_name == "solo"
    assert state.ws_next_id == 2
    assert [%{name: "builder"}] = state.ws_agents
  end

  test "spawn_order walks roots before children" do
    agents = [%{id: 1}, %{id: 2}, %{id: 3}]
    links = [%{from: 1, to: 2}, %{from: 2, to: 3}]

    assert Enum.map(Presets.spawn_order(agents, links), & &1.id) == [1, 2, 3]
  end
end
