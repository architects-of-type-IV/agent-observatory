defmodule WorkshopCanvas.PresetTest do
  use ExUnit.Case, async: false

  alias WorkshopCanvas.Agent
  alias WorkshopCanvas.Preset

  doctest WorkshopCanvas.Preset

  setup do
    on_exit(fn -> Application.delete_env(:workshop_canvas, :presets) end)
    {:ok, state: WorkshopCanvas.defaults()}
  end

  describe "the built-in preset" do
    test "is registered" do
      assert "pair" in Preset.names()
    end

    test "appears in the picker list with a label and colour" do
      assert [%{name: "pair", label: label, color: color}] = Preset.ui_list()
      assert is_binary(label)
      assert is_binary(color)
    end

    test "applies onto a canvas", %{state: state} do
      state = Preset.apply(state, "pair")

      assert length(state.ws_agents) == 2
      assert state.ws_team_name == "pair"
      assert length(state.ws_spawn_links) == 1
      assert length(state.ws_comm_rules) == 2
    end
  end

  describe "apply/2" do
    test "completes agents so they are immediately editable", %{state: state} do
      state = Preset.apply(state, "pair")

      for agent <- state.ws_agents,
          key <- Agent.keys(),
          do: assert(Map.has_key?(agent, key), "missing #{key}")

      assert %{ws_agents: [%{name: "renamed"} | _]} =
               WorkshopCanvas.update_agent(state, 1, %{"name" => "renamed"})
    end

    test "derives next_id past the highest slot", %{state: state} do
      Application.put_env(:workshop_canvas, :presets, %{
        "sparse" => %Preset{label: "Sparse", agents: [%{id: 3, name: "a"}, %{id: 9, name: "b"}]}
      })

      state = Preset.apply(state, "sparse")

      assert state.ws_next_id == 10
    end

    test "an unknown name leaves the canvas untouched", %{state: state} do
      populated = WorkshopCanvas.add_agent(state, %{name: "mine"})

      assert Preset.apply(populated, "no-such-preset") == populated
    end

    test "clears the selection", %{state: state} do
      state = state |> WorkshopCanvas.add_agent(%{name: "a"}) |> Preset.apply("pair")

      assert state.ws_selected_agent == nil
    end

    test "replaces rather than merges the previous contents", %{state: state} do
      state =
        state
        |> WorkshopCanvas.add_agent(%{name: "leftover"})
        |> Preset.apply("pair")

      refute Enum.any?(state.ws_agents, &(&1.name == "leftover"))
    end

    test "lays preset agents out on the grid", %{state: state} do
      state = Preset.apply(state, "pair")

      assert [{40, 30}, {270, 30}] = Enum.map(state.ws_agents, &{&1.x, &1.y})
    end

    test "an empty preset yields an empty canvas", %{state: state} do
      Application.put_env(:workshop_canvas, :presets, %{
        "empty" => %Preset{label: "Empty"}
      })

      state = Preset.apply(state, "empty")

      assert state.ws_agents == []
      assert state.ws_next_id == 1
      assert state.ws_team_name == "alpha"
    end
  end

  describe "custom presets" do
    setup do
      Application.put_env(:workshop_canvas, :presets, %{
        "review" => %Preset{
          label: "Code review",
          color: "#7c3aed",
          team_name: "review",
          model: "opus",
          agents: [
            %{id: 1, name: "lead", capability: "coordinator"},
            %{id: 2, name: "reviewer", capability: "scout"}
          ],
          links: [%{from: 1, to: 2}],
          rules: [%{from: 1, to: 2, policy: "allow", via: nil}]
        }
      })

      :ok
    end

    test "replace the built-ins rather than merging" do
      assert Preset.names() == ["review"]
      assert Preset.fetch("pair") == :error
    end

    test "apply their team name and model", %{state: state} do
      state = Preset.apply(state, "review")

      assert state.ws_team_name == "review"
      assert state.ws_default_model == "opus"
    end

    test "give agents the preset's model when they name none", %{state: state} do
      state = Preset.apply(state, "review")

      assert Enum.all?(state.ws_agents, &(&1.model == "opus"))
    end

    test "produce a launchable spawn order", %{state: state} do
      state = Preset.apply(state, "review")

      assert Enum.map(WorkshopCanvas.spawn_order(state), & &1.name) == ["lead", "reviewer"]
    end

    test "produce a canvas with no problems", %{state: state} do
      state = Preset.apply(state, "review")

      assert WorkshopCanvas.problems(state) == []
    end
  end

  describe "fetch/1" do
    test "returns a registered preset" do
      assert {:ok, %Preset{label: _}} = Preset.fetch("pair")
    end

    test "reports an unknown one" do
      assert Preset.fetch("nope") == :error
    end
  end
end
