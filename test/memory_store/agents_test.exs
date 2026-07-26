defmodule MemoryStore.AgentsTest do
  use MemoryStore.StoreCase

  describe "create_agent/3" do
    test "creates the agent and its blocks" do
      assert {:ok, agent} =
               MemoryStore.create_agent("scout", [
                 %{label: "persona", value: "You survey codebases."},
                 %{label: "human", value: "Terse."}
               ])

      assert agent.name == "scout"
      assert length(agent.block_ids) == 2
      assert {:ok, blocks} = MemoryStore.list_blocks()
      assert length(blocks) == 2
    end

    test "preserves the order the blocks were given in" do
      {:ok, _} =
        MemoryStore.create_agent("scout", [
          %{label: "first", value: "1"},
          %{label: "second", value: "2"},
          %{label: "third", value: "3"}
        ])

      {:ok, core} = MemoryStore.read_core_memory("scout")
      assert Enum.map(core.blocks, & &1.label) == ["first", "second", "third"]
    end

    test "attaches existing blocks after the new ones" do
      {:ok, shared} = MemoryStore.create_block(%{label: "org", value: "Acme"})

      {:ok, _} = MemoryStore.create_agent("scout", [%{label: "persona"}], [shared.id])

      {:ok, core} = MemoryStore.read_core_memory("scout")
      assert Enum.map(core.blocks, & &1.label) == ["persona", "org"]
    end

    test "works with no blocks at all" do
      assert {:ok, agent} = MemoryStore.create_agent("bare")
      assert agent.block_ids == []
    end

    test "refuses a duplicate name" do
      {:ok, _} = MemoryStore.create_agent("scout")

      assert {:error, :already_exists} = MemoryStore.create_agent("scout")
    end

    @tag max_agents: 1
    test "refuses past the agent ceiling" do
      {:ok, _} = MemoryStore.create_agent("one")

      assert {:error, :max_agents_reached} = MemoryStore.create_agent("two")
    end
  end

  describe "get_agent/1" do
    test "returns the record" do
      {:ok, _} = MemoryStore.create_agent("scout")

      assert {:ok, agent} = MemoryStore.get_agent("scout")
      assert agent.name == "scout"
    end

    test "reports a missing agent" do
      assert {:error, :not_found} = MemoryStore.get_agent("ghost")
    end
  end

  describe "list_agents/0" do
    test "includes block labels and tier counts" do
      {:ok, _} = MemoryStore.create_agent("scout", [%{label: "persona"}, %{label: "human"}])
      {:ok, _} = MemoryStore.add_recall("scout", :user, "hello")
      {:ok, _} = MemoryStore.archival_memory_insert("scout", "a fact")

      assert {:ok, [agent]} = MemoryStore.list_agents()
      assert agent.block_labels == ["persona", "human"]
      assert agent.recall_count == 1
      assert agent.archival_count == 1
    end

    test "is empty to begin with" do
      assert {:ok, []} = MemoryStore.list_agents()
    end
  end

  describe "attach_block/2 and detach_block/2" do
    setup do
      {:ok, _} = MemoryStore.create_agent("scout", [%{label: "persona"}])
      {:ok, shared} = MemoryStore.create_block(%{label: "org", value: "Acme"})
      {:ok, shared: shared}
    end

    test "attach adds the block", %{shared: shared} do
      assert {:ok, agent} = MemoryStore.attach_block("scout", shared.id)
      assert shared.id in agent.block_ids
    end

    test "attach is idempotent", %{shared: shared} do
      {:ok, _} = MemoryStore.attach_block("scout", shared.id)
      {:ok, agent} = MemoryStore.attach_block("scout", shared.id)

      assert Enum.count(agent.block_ids, &(&1 == shared.id)) == 1
    end

    test "attach reports a missing agent", %{shared: shared} do
      assert {:error, :not_found} = MemoryStore.attach_block("ghost", shared.id)
    end

    test "attach reports a missing block" do
      assert {:error, :not_found} = MemoryStore.attach_block("scout", "nope")
    end

    test "detach removes the block but keeps it in the store", %{shared: shared} do
      {:ok, _} = MemoryStore.attach_block("scout", shared.id)

      assert {:ok, agent} = MemoryStore.detach_block("scout", shared.id)
      refute shared.id in agent.block_ids
      assert {:ok, _} = MemoryStore.get_block(shared.id)
    end

    test "detach reports a missing agent", %{shared: shared} do
      assert {:error, :not_found} = MemoryStore.detach_block("ghost", shared.id)
    end

    test "a shared block is visible to both agents", %{shared: shared} do
      {:ok, _} = MemoryStore.create_agent("other", [], [shared.id])
      {:ok, _} = MemoryStore.attach_block("scout", shared.id)

      {:ok, _} = MemoryStore.memory_rethink("scout", "org", "Acme Corp")

      {:ok, core} = MemoryStore.read_core_memory("other")
      assert Enum.find(core.blocks, &(&1.label == "org")).value == "Acme Corp"
    end
  end

  describe "read_core_memory/1" do
    test "returns blocks plus tier counts" do
      {:ok, _} =
        MemoryStore.create_agent("scout", [
          %{label: "persona", value: "v", description: "d", read_only: true}
        ])

      assert {:ok, core} = MemoryStore.read_core_memory("scout")
      assert core.agent == "scout"
      assert core.recall_count == 0
      assert core.archival_count == 0

      assert [%{label: "persona", value: "v", description: "d", read_only: true}] = core.blocks
    end

    test "reports a missing agent" do
      assert {:error, :not_found} = MemoryStore.read_core_memory("ghost")
    end
  end

  describe "compile_memory/1" do
    test "wraps each block in a labelled tag" do
      {:ok, _} = MemoryStore.create_agent("scout", [%{label: "persona", value: "I survey."}])

      assert {:ok, text} = MemoryStore.compile_memory("scout")
      assert text =~ ~s(<memory_block label="persona" read_only="false">)
      assert text =~ "I survey."
      assert text =~ "</memory_block>"
    end

    test "includes the description as a comment when present" do
      {:ok, _} =
        MemoryStore.create_agent("scout", [
          %{label: "persona", value: "v", description: "who I am"}
        ])

      {:ok, text} = MemoryStore.compile_memory("scout")
      assert text =~ "<!-- who I am -->"
    end

    test "omits the comment when there is no description" do
      {:ok, _} = MemoryStore.create_agent("scout", [%{label: "persona", value: "v"}])

      {:ok, text} = MemoryStore.compile_memory("scout")
      refute text =~ "<!--"
    end

    test "separates blocks with a blank line" do
      {:ok, _} =
        MemoryStore.create_agent("scout", [
          %{label: "a", value: "1"},
          %{label: "b", value: "2"}
        ])

      {:ok, text} = MemoryStore.compile_memory("scout")
      assert text =~ "</memory_block>\n\n<memory_block"
    end

    test "reports a missing agent" do
      assert {:error, :not_found} = MemoryStore.compile_memory("ghost")
    end
  end
end
