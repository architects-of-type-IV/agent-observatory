defmodule EmbeddedLink do
  @moduledoc "Stands in for a host's embedded-resource struct in apply_team/2 tests."
  defstruct [:from, :to]
end

defmodule WorkshopCanvasTest do
  use ExUnit.Case, async: false

  alias WorkshopCanvas.Agent

  doctest WorkshopCanvas.Agent

  setup do
    on_exit(fn ->
      for key <- Map.keys(WorkshopCanvas.Config.all()) ++ [:presets] do
        Application.delete_env(:workshop_canvas, key)
      end
    end)

    {:ok, state: WorkshopCanvas.defaults()}
  end

  defp with_agents(state, names) do
    Enum.reduce(names, state, fn name, acc -> WorkshopCanvas.add_agent(acc, %{name: name}) end)
  end

  describe "defaults/0" do
    test "starts empty", %{state: state} do
      assert state.ws_agents == []
      assert state.ws_spawn_links == []
      assert state.ws_comm_rules == []
      assert state.ws_selected_agent == nil
      assert state.ws_next_id == 1
      assert state.ws_team_id == nil
    end

    test "uses the configured team defaults" do
      Application.put_env(:workshop_canvas, :default_team_name, "custom")
      Application.put_env(:workshop_canvas, :default_model, "opus")

      state = WorkshopCanvas.defaults()

      assert state.ws_team_name == "custom"
      assert state.ws_default_model == "opus"
    end
  end

  describe "clear/1" do
    test "resets canvas fields but leaves the rest of the map alone", %{state: state} do
      assigns =
        state
        |> WorkshopCanvas.add_agent(%{name: "a"})
        |> Map.put(:unrelated_page_field, "keep me")

      cleared = WorkshopCanvas.clear(assigns)

      assert cleared.ws_agents == []
      assert cleared.ws_next_id == 1
      assert cleared.unrelated_page_field == "keep me"
    end
  end

  describe "add_agent/2" do
    test "adds, selects, and advances the id", %{state: state} do
      state = WorkshopCanvas.add_agent(state, %{name: "coordinator"})

      assert [%{id: 1, name: "coordinator"}] = state.ws_agents
      assert state.ws_selected_agent == 1
      assert state.ws_next_id == 2
    end

    test "fills every field so later edits cannot crash", %{state: state} do
      state = WorkshopCanvas.add_agent(state, %{name: "a"})
      [agent] = state.ws_agents

      for key <- Agent.keys(), do: assert(Map.has_key?(agent, key), "missing #{key}")
    end

    test "inherits the canvas default model", %{state: state} do
      state = %{state | ws_default_model: "opus"}
      state = WorkshopCanvas.add_agent(state, %{name: "a"})

      assert [%{model: "opus"}] = state.ws_agents
    end

    test "an explicit model wins over the default", %{state: state} do
      state = WorkshopCanvas.add_agent(state, %{name: "a", model: "haiku"})

      assert [%{model: "haiku"}] = state.ws_agents
    end

    test "lays agents out on a grid", %{state: state} do
      state = with_agents(state, ["a", "b", "c", "d"])
      positions = Enum.map(state.ws_agents, &{&1.x, &1.y})

      assert [{40, 30}, {270, 30}, {500, 30}, {40, 200}] = positions
    end

    test "ids keep advancing after a removal", %{state: state} do
      state =
        state
        |> with_agents(["a", "b"])
        |> WorkshopCanvas.remove_agent(1)
        |> WorkshopCanvas.add_agent(%{name: "c"})

      assert Enum.map(state.ws_agents, & &1.id) == [2, 3]
    end
  end

  describe "update_agent/3" do
    setup %{state: state} do
      {:ok, state: WorkshopCanvas.add_agent(state, %{name: "a", persona: "original"})}
    end

    test "applies string-keyed params", %{state: state} do
      state = WorkshopCanvas.update_agent(state, 1, %{"name" => "renamed"})

      assert [%{name: "renamed"}] = state.ws_agents
    end

    test "leaves unsupplied fields alone", %{state: state} do
      state = WorkshopCanvas.update_agent(state, 1, %{"name" => "renamed"})

      assert [%{persona: "original"}] = state.ws_agents
    end

    test "updates every editable field", %{state: state} do
      params = %{
        "name" => "n",
        "capability" => "scout",
        "model" => "haiku",
        "permission" => "strict",
        "persona" => "p",
        "file_scope" => "lib/**",
        "quality_gates" => "mix test"
      }

      state = WorkshopCanvas.update_agent(state, 1, params)
      [agent] = state.ws_agents

      assert agent.capability == "scout"
      assert agent.file_scope == "lib/**"
      assert agent.quality_gates == "mix test"
    end

    test "does not move the agent", %{state: state} do
      [before] = state.ws_agents
      state = WorkshopCanvas.update_agent(state, 1, %{"name" => "n"})

      assert [%{x: x, y: y}] = state.ws_agents
      assert {x, y} == {before.x, before.y}
    end

    test "an unknown id changes nothing", %{state: state} do
      assert WorkshopCanvas.update_agent(state, 99, %{"name" => "x"}) == state
    end
  end

  describe "move_agent/4" do
    test "sets coordinates", %{state: state} do
      state =
        state
        |> WorkshopCanvas.add_agent(%{name: "a"})
        |> WorkshopCanvas.move_agent(1, 500, 400)

      assert [%{x: 500, y: 400}] = state.ws_agents
    end

    test "moves only the named agent", %{state: state} do
      state =
        state
        |> with_agents(["a", "b"])
        |> WorkshopCanvas.move_agent(1, 500, 400)

      assert [%{id: 1, x: 500}, %{id: 2, x: 270}] = state.ws_agents
    end
  end

  describe "remove_agent/2" do
    setup %{state: state} do
      state =
        state
        |> with_agents(["a", "b", "c"])
        |> WorkshopCanvas.add_spawn_link(1, 2)
        |> WorkshopCanvas.add_spawn_link(2, 3)
        |> WorkshopCanvas.add_comm_rule(1, 2, "allow")
        |> WorkshopCanvas.add_comm_rule(3, 1, "route", 2)

      {:ok, state: state}
    end

    test "removes the agent", %{state: state} do
      state = WorkshopCanvas.remove_agent(state, 2)

      assert Enum.map(state.ws_agents, & &1.id) == [1, 3]
    end

    test "cascades to spawn links on either end", %{state: state} do
      state = WorkshopCanvas.remove_agent(state, 2)

      assert state.ws_spawn_links == []
    end

    test "cascades to comm rules on either end", %{state: state} do
      state = WorkshopCanvas.remove_agent(state, 1)

      refute Enum.any?(state.ws_comm_rules, &(&1.from == 1 or &1.to == 1))
    end

    test "cascades to a rule that only referenced it as a relay", %{state: state} do
      # Leaving this would route messages through a slot that no longer exists.
      state = WorkshopCanvas.remove_agent(state, 2)

      refute Enum.any?(state.ws_comm_rules, &(Map.get(&1, :via) == 2))
    end

    test "clears the selection", %{state: state} do
      state = WorkshopCanvas.remove_agent(state, 3)

      assert state.ws_selected_agent == nil
    end

    test "removing an unknown id is a no-op on the agent list", %{state: state} do
      assert WorkshopCanvas.remove_agent(state, 99).ws_agents == state.ws_agents
    end
  end

  describe "add_spawn_link/3" do
    setup %{state: state}, do: {:ok, state: with_agents(state, ["a", "b"])}

    test "adds a link", %{state: state} do
      state = WorkshopCanvas.add_spawn_link(state, 1, 2)

      assert state.ws_spawn_links == [%{from: 1, to: 2}]
    end

    test "is idempotent", %{state: state} do
      state =
        state
        |> WorkshopCanvas.add_spawn_link(1, 2)
        |> WorkshopCanvas.add_spawn_link(1, 2)

      assert length(state.ws_spawn_links) == 1
    end

    test "dedups the reverse direction too", %{state: state} do
      state =
        state
        |> WorkshopCanvas.add_spawn_link(1, 2)
        |> WorkshopCanvas.add_spawn_link(2, 1)

      assert length(state.ws_spawn_links) == 1
    end

    test "remove_spawn_link/2 deletes by index", %{state: state} do
      state =
        state
        |> WorkshopCanvas.add_spawn_link(1, 2)
        |> WorkshopCanvas.remove_spawn_link(0)

      assert state.ws_spawn_links == []
    end
  end

  describe "add_comm_rule/5" do
    setup %{state: state}, do: {:ok, state: with_agents(state, ["a", "b"])}

    test "adds a rule with a nil relay by default", %{state: state} do
      state = WorkshopCanvas.add_comm_rule(state, 1, 2, "allow")

      assert state.ws_comm_rules == [%{from: 1, to: 2, policy: "allow", via: nil}]
    end

    test "accepts a relay", %{state: state} do
      state = WorkshopCanvas.add_comm_rule(state, 1, 2, "route", 3)

      assert [%{via: 3}] = state.ws_comm_rules
    end

    test "is idempotent per from/to/policy", %{state: state} do
      state =
        state
        |> WorkshopCanvas.add_comm_rule(1, 2, "allow")
        |> WorkshopCanvas.add_comm_rule(1, 2, "allow")

      assert length(state.ws_comm_rules) == 1
    end

    test "is directional, unlike spawn links", %{state: state} do
      state =
        state
        |> WorkshopCanvas.add_comm_rule(1, 2, "allow")
        |> WorkshopCanvas.add_comm_rule(2, 1, "allow")

      assert length(state.ws_comm_rules) == 2
    end

    test "a different policy between the same pair is a separate rule", %{state: state} do
      state =
        state
        |> WorkshopCanvas.add_comm_rule(1, 2, "allow")
        |> WorkshopCanvas.add_comm_rule(1, 2, "route", 3)

      assert length(state.ws_comm_rules) == 2
    end

    test "remove_comm_rule/2 deletes by index", %{state: state} do
      state =
        state
        |> WorkshopCanvas.add_comm_rule(1, 2, "allow")
        |> WorkshopCanvas.remove_comm_rule(0)

      assert state.ws_comm_rules == []
    end
  end

  describe "update_team/2" do
    test "applies team params", %{state: state} do
      state =
        WorkshopCanvas.update_team(state, %{
          "name" => "beta",
          "strategy" => "one_for_all",
          "default_model" => "opus",
          "cwd" => "/srv"
        })

      assert state.ws_team_name == "beta"
      assert state.ws_strategy == "one_for_all"
      assert state.ws_default_model == "opus"
      assert state.ws_cwd == "/srv"
    end

    test "leaves unsupplied fields alone", %{state: state} do
      state = WorkshopCanvas.update_team(state, %{"name" => "beta"})

      assert state.ws_strategy == "one_for_one"
    end
  end

  describe "apply_team/2" do
    test "loads a persisted team", %{state: state} do
      team = %{
        id: "team-1",
        name: "loaded",
        strategy: "one_for_all",
        default_model: "opus",
        cwd: "/srv",
        agents: [%{id: 1, name: "a"}, %{id: 5, name: "b"}],
        spawn_links: [%{from: 1, to: 5}],
        comm_rules: [%{from: 1, to: 5, policy: "allow", via: nil}]
      }

      state = WorkshopCanvas.apply_team(state, team)

      assert state.ws_team_id == "team-1"
      assert state.ws_team_name == "loaded"
      assert length(state.ws_agents) == 2
      assert state.ws_spawn_links == [%{from: 1, to: 5}]
    end

    test "derives next_id from the highest slot, not the count", %{state: state} do
      team = %{name: "t", agents: [%{id: 1, name: "a"}, %{id: 7, name: "b"}]}

      state = WorkshopCanvas.apply_team(state, team)

      assert state.ws_next_id == 8
    end

    test "completes agents missing fields from an older schema", %{state: state} do
      team = %{name: "t", agents: [%{id: 1, name: "a"}]}

      state = WorkshopCanvas.apply_team(state, team)
      [agent] = state.ws_agents

      for key <- Agent.keys(), do: assert(Map.has_key?(agent, key), "missing #{key}")

      # And the completed agent survives an edit.
      assert %{ws_agents: [%{name: "renamed"}]} =
               WorkshopCanvas.update_agent(state, 1, %{"name" => "renamed"})
    end

    test "handles a team with no agents", %{state: state} do
      state = WorkshopCanvas.apply_team(state, %{name: "empty"})

      assert state.ws_agents == []
      assert state.ws_next_id == 1
    end

    test "converts embedded structs to maps", %{state: state} do
      team = %{name: "t", agents: [], spawn_links: [%EmbeddedLink{from: 1, to: 2}]}

      state = WorkshopCanvas.apply_team(state, team)

      assert state.ws_spawn_links == [%{from: 1, to: 2}]
    end

    test "clears the selection", %{state: state} do
      state = WorkshopCanvas.add_agent(state, %{name: "a"})
      state = WorkshopCanvas.apply_team(state, %{name: "t", agents: []})

      assert state.ws_selected_agent == nil
    end
  end

  describe "to_persistence_params/1" do
    test "round-trips through apply_team", %{state: state} do
      original =
        state
        |> with_agents(["a", "b"])
        |> WorkshopCanvas.add_spawn_link(1, 2)
        |> WorkshopCanvas.add_comm_rule(1, 2, "allow")
        |> WorkshopCanvas.update_team(%{"name" => "beta", "cwd" => "/srv"})

      params = WorkshopCanvas.to_persistence_params(original)
      reloaded = WorkshopCanvas.apply_team(WorkshopCanvas.defaults(), params)

      assert reloaded.ws_team_name == "beta"
      assert reloaded.ws_cwd == "/srv"
      assert reloaded.ws_agents == original.ws_agents
      assert reloaded.ws_spawn_links == original.ws_spawn_links
      assert reloaded.ws_comm_rules == original.ws_comm_rules
    end
  end

  describe "queries" do
    test "selected_agent/1 returns the selection", %{state: state} do
      state = with_agents(state, ["a", "b"])

      assert %{id: 2, name: "b"} = WorkshopCanvas.selected_agent(state)
    end

    test "selected_agent/1 is nil with no selection", %{state: state} do
      assert WorkshopCanvas.selected_agent(state) == nil
    end

    test "get_agent/2 looks up by id", %{state: state} do
      state = with_agents(state, ["a", "b"])

      assert %{name: "a"} = WorkshopCanvas.get_agent(state, 1)
      assert WorkshopCanvas.get_agent(state, 99) == nil
    end

    test "spawn_order/1 orders the canvas", %{state: state} do
      state =
        state
        |> with_agents(["a", "b", "c"])
        |> WorkshopCanvas.add_spawn_link(1, 2)
        |> WorkshopCanvas.add_spawn_link(2, 3)

      assert Enum.map(WorkshopCanvas.spawn_order(state), & &1.name) == ["a", "b", "c"]
    end
  end

  describe "problems/1" do
    test "a coherent canvas has none", %{state: state} do
      state =
        state
        |> with_agents(["a", "b"])
        |> WorkshopCanvas.add_spawn_link(1, 2)
        |> WorkshopCanvas.add_comm_rule(1, 2, "allow")

      assert WorkshopCanvas.problems(state) == []
    end

    test "flags duplicate names, which would share an inbox", %{state: state} do
      state = with_agents(state, ["dup", "dup"])

      assert {:duplicate_name, "dup"} in WorkshopCanvas.problems(state)
    end

    test "flags a link to a missing slot", %{state: state} do
      state = with_agents(state, ["a"])
      state = Map.put(state, :ws_spawn_links, [%{from: 1, to: 99}])

      assert [{:dangling_link, %{to: 99}}] = WorkshopCanvas.problems(state)
    end

    test "flags a rule to a missing slot", %{state: state} do
      state = with_agents(state, ["a"])
      state = Map.put(state, :ws_comm_rules, [%{from: 1, to: 99, policy: "allow", via: nil}])

      assert [{:dangling_rule, %{to: 99}}] = WorkshopCanvas.problems(state)
    end

    test "flags a spawn cycle", %{state: state} do
      state =
        state
        |> with_agents(["a", "b"])
        |> WorkshopCanvas.add_spawn_link(1, 2)

      state = Map.put(state, :ws_spawn_links, [%{from: 1, to: 2}, %{from: 2, to: 1}])

      assert [{:spawn_cycle, ids}] = WorkshopCanvas.problems(state)
      assert Enum.sort(ids) == [1, 2]
    end
  end

  describe "agent_type_agent/3" do
    test "builds from a reusable type record", %{state: state} do
      type = %{
        id: "type-1",
        name: "scout",
        capability: "scout",
        default_model: "haiku",
        default_permission: "strict",
        default_persona: "You survey.",
        default_file_scope: "lib/**",
        default_quality_gates: "mix test",
        default_tools: ["Read"]
      }

      agent = WorkshopCanvas.agent_type_agent(state, type, 2)

      assert agent.name == "scout-2"
      assert agent.capability == "scout"
      assert agent.model == "haiku"
      assert agent.agent_type_id == "type-1"
      assert agent.tools == ["Read"]
    end

    test "falls back to defaults for a sparse type", %{state: state} do
      agent = WorkshopCanvas.agent_type_agent(state, %{name: "bare"}, 0)

      assert agent.capability == "builder"
      assert agent.model == "sonnet"
      assert agent.tools == []
    end
  end
end
