defmodule Ichor.Workshop.AgentTypeTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Ichor.Workshop.AgentType

  # Ash string type converts "" to nil by default (allow_empty?: false).
  # default_persona, default_file_scope, and color all have default("") +
  # allow_nil?(false), meaning they must be supplied explicitly with non-empty
  # values. We use a shared helper to provide the minimum valid params.
  defp base_params(overrides \\ %{}) do
    Map.merge(
      %{
        default_persona: "default",
        default_file_scope: ".",
        color: "#000000"
      },
      overrides
    )
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Ichor.Repo)
  end

  describe "create" do
    test "creates an agent type with valid name" do
      params = base_params(%{name: "builder-#{System.unique_integer([:positive])}"})
      assert {:ok, at} = AgentType.create(params)
      assert at.name != nil
    end

    test "applies capability default" do
      params = base_params(%{name: "cap-#{System.unique_integer([:positive])}"})
      assert {:ok, at} = AgentType.create(params)
      assert at.capability == "builder"
    end

    test "applies default_model default" do
      params = base_params(%{name: "mdl-#{System.unique_integer([:positive])}"})
      assert {:ok, at} = AgentType.create(params)
      assert at.default_model == "sonnet"
    end

    test "applies default_permission default" do
      params = base_params(%{name: "perm-#{System.unique_integer([:positive])}"})
      assert {:ok, at} = AgentType.create(params)
      assert at.default_permission == "default"
    end

    test "applies sort_order default" do
      params = base_params(%{name: "sort-#{System.unique_integer([:positive])}"})
      assert {:ok, at} = AgentType.create(params)
      assert at.sort_order == 0
    end

    test "accepts all fields" do
      assert {:ok, at} =
               AgentType.create(%{
                 name: "full-#{System.unique_integer([:positive])}",
                 capability: "reviewer",
                 default_model: "haiku",
                 default_permission: "readonly",
                 default_persona: "You are a strict reviewer.",
                 default_file_scope: "lib/",
                 default_quality_gates: "mix test",
                 default_tools: ["Read", "Grep"],
                 color: "#ff6600",
                 sort_order: 5
               })

      assert at.capability == "reviewer"
      assert at.default_model == "haiku"
      assert at.default_permission == "readonly"
      assert at.default_persona == "You are a strict reviewer."
      assert at.default_file_scope == "lib/"
      assert at.default_tools == ["Read", "Grep"]
      assert at.color == "#ff6600"
      assert at.sort_order == 5
    end

    test "rejects missing name" do
      params = base_params()
      assert {:error, _} = AgentType.create(params)
    end

    test "rejects duplicate name" do
      name = "dup-at-#{System.unique_integer([:positive])}"
      params = base_params(%{name: name})
      assert {:ok, _} = AgentType.create(params)
      assert {:error, _} = AgentType.create(params)
    end
  end

  describe "read" do
    test "reads all agent types" do
      assert {:ok, types} = AgentType.read()
      assert is_list(types)
    end

    test "by_id finds agent type" do
      params = base_params(%{name: "find-at-#{System.unique_integer([:positive])}"})
      {:ok, created} = AgentType.create(params)
      assert {:ok, found} = AgentType.by_id(created.id)
      assert found.id == created.id
    end

    test "sorted returns agent types ordered by sort_order then name" do
      suffix = System.unique_integer([:positive])
      {:ok, _} = AgentType.create(base_params(%{name: "zz-sorted-#{suffix}", sort_order: 2}))
      {:ok, _} = AgentType.create(base_params(%{name: "aa-sorted-#{suffix}", sort_order: 1}))
      assert {:ok, types} = AgentType.sorted()
      assert is_list(types)
      sort_orders = Enum.map(types, & &1.sort_order)
      # Sorted ascending by sort_order
      assert sort_orders == Enum.sort(sort_orders)
    end
  end

  describe "update" do
    test "updates capability" do
      {:ok, at} =
        AgentType.create(base_params(%{name: "upd-cap-#{System.unique_integer([:positive])}"}))

      assert {:ok, updated} = AgentType.update(at, %{capability: "architect"})
      assert updated.capability == "architect"
    end

    test "updates default_model" do
      {:ok, at} =
        AgentType.create(base_params(%{name: "upd-mdl-#{System.unique_integer([:positive])}"}))

      assert {:ok, updated} = AgentType.update(at, %{default_model: "opus"})
      assert updated.default_model == "opus"
    end

    test "updates default_tools list" do
      {:ok, at} =
        AgentType.create(base_params(%{name: "upd-tools-#{System.unique_integer([:positive])}"}))

      assert {:ok, updated} = AgentType.update(at, %{default_tools: ["Bash", "Read"]})
      assert updated.default_tools == ["Bash", "Read"]
    end

    test "updates sort_order" do
      {:ok, at} =
        AgentType.create(base_params(%{name: "upd-sort-#{System.unique_integer([:positive])}"}))

      assert {:ok, updated} = AgentType.update(at, %{sort_order: 99})
      assert updated.sort_order == 99
    end
  end

  describe "destroy" do
    test "destroys an agent type" do
      {:ok, at} =
        AgentType.create(base_params(%{name: "del-at-#{System.unique_integer([:positive])}"}))

      assert :ok = AgentType.destroy(at)
    end

    test "destroyed agent type is no longer found by id" do
      {:ok, at} =
        AgentType.create(base_params(%{name: "gone-at-#{System.unique_integer([:positive])}"}))

      :ok = AgentType.destroy(at)
      assert {:error, _} = AgentType.by_id(at.id)
    end
  end
end
