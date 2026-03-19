defmodule Ichor.Workshop.BlueprintStateTest do
  use ExUnit.Case, async: true

  alias Ichor.Workshop.BlueprintState

  test "add_agent increments ids and selects new agent" do
    state =
      BlueprintState.defaults()
      |> BlueprintState.add_agent(%{name: "builder-1"})

    assert state.ws_next_id == 2
    assert state.ws_selected_agent == 1
    assert [%{id: 1, name: "builder-1"}] = state.ws_agents
  end

  test "remove_agent removes linked spawn and comm rules" do
    state = %{
      BlueprintState.defaults()
      | ws_agents: [%{id: 1}, %{id: 2}],
        ws_spawn_links: [%{from: 1, to: 2}],
        ws_comm_rules: [%{from: 1, to: 2, policy: "allow", via: nil}]
    }

    state = BlueprintState.remove_agent(state, 1)

    assert state.ws_agents == [%{id: 2}]
    assert state.ws_spawn_links == []
    assert state.ws_comm_rules == []
    assert is_nil(state.ws_selected_agent)
  end

  test "apply_blueprint loads persisted shapes into canvas state" do
    blueprint = %{
      id: "bp-1",
      name: "alpha",
      strategy: "one_for_one",
      default_model: "sonnet",
      cwd: "/tmp/app",
      agent_blueprints: [
        %{
          slot: 2,
          name: "lead",
          capability: "lead",
          model: "opus",
          permission: "default",
          persona: "",
          file_scope: "",
          quality_gates: "",
          canvas_x: 10,
          canvas_y: 20
        }
      ],
      spawn_links: [%{from_slot: 2, to_slot: 3}],
      comm_rules: [%{from_slot: 2, to_slot: 3, policy: "allow", via_slot: nil}]
    }

    state = BlueprintState.apply_blueprint(BlueprintState.defaults(), blueprint)

    assert state.ws_blueprint_id == "bp-1"
    assert state.ws_team_name == "alpha"
    assert state.ws_next_id == 3
    assert [%{id: 2, x: 10, y: 20}] = state.ws_agents
    assert [%{from: 2, to: 3}] = state.ws_spawn_links
    assert [%{from: 2, to: 3, policy: "allow", via: nil}] = state.ws_comm_rules
  end
end
