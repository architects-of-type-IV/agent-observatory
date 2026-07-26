defmodule MemoryStore.BlocksTest do
  use MemoryStore.StoreCase

  describe "create_block/1" do
    test "creates a block with defaults filled in" do
      assert {:ok, block} = MemoryStore.create_block(%{label: "persona"})

      assert block.label == "persona"
      assert block.value == ""
      assert block.description == ""
      assert block.read_only == false
      assert block.limit == MemoryStore.Config.default_block_limit()
      assert block.created_at == block.updated_at
    end

    test "accepts string keys" do
      assert {:ok, block} = MemoryStore.create_block(%{"label" => "human", "value" => "Ada"})

      assert block.label == "human"
      assert block.value == "Ada"
    end

    test "ids are unique" do
      {:ok, a} = MemoryStore.create_block(%{label: "one"})
      {:ok, b} = MemoryStore.create_block(%{label: "one"})

      refute a.id == b.id
    end

    @tag max_blocks: 2
    test "refuses past the block ceiling" do
      {:ok, _} = MemoryStore.create_block(%{label: "a"})
      {:ok, _} = MemoryStore.create_block(%{label: "b"})

      assert {:error, :max_blocks_reached} = MemoryStore.create_block(%{label: "c"})
    end
  end

  describe "get_block/1" do
    test "returns the block" do
      {:ok, created} = MemoryStore.create_block(%{label: "persona", value: "v"})

      assert {:ok, found} = MemoryStore.get_block(created.id)
      assert found.id == created.id
    end

    test "reports a missing block" do
      assert {:error, :not_found} = MemoryStore.get_block("nope")
    end
  end

  describe "update_block/2" do
    setup do
      {:ok, block} = MemoryStore.create_block(%{label: "persona", value: "before"})
      {:ok, block: block}
    end

    test "updates value, description, and limit", %{block: block} do
      assert {:ok, updated} =
               MemoryStore.update_block(block.id, %{
                 value: "after",
                 description: "who I am",
                 limit: 50
               })

      assert updated.value == "after"
      assert updated.description == "who I am"
      assert updated.limit == 50
    end

    test "leaves untouched fields alone", %{block: block} do
      {:ok, updated} = MemoryStore.update_block(block.id, %{value: "after"})

      assert updated.label == "persona"
      assert updated.limit == block.limit
    end

    test "accepts string keys", %{block: block} do
      assert {:ok, updated} = MemoryStore.update_block(block.id, %{"value" => "str"})
      assert updated.value == "str"
    end

    test "rejects a value past the limit", %{block: block} do
      {:ok, _} = MemoryStore.update_block(block.id, %{limit: 10})

      assert {:error, :exceeds_limit} =
               MemoryStore.update_block(block.id, %{value: "far too long for ten"})

      assert {:ok, %{value: "before"}} = MemoryStore.get_block(block.id)
    end

    test "rejects lowering the limit below the current value", %{block: block} do
      assert {:error, :exceeds_limit} = MemoryStore.update_block(block.id, %{limit: 2})
    end

    test "reports a missing block" do
      assert {:error, :not_found} = MemoryStore.update_block("nope", %{value: "x"})
    end
  end

  describe "list_blocks/1" do
    test "returns every block" do
      {:ok, _} = MemoryStore.create_block(%{label: "a"})
      {:ok, _} = MemoryStore.create_block(%{label: "b"})

      assert {:ok, blocks} = MemoryStore.list_blocks()
      assert length(blocks) == 2
    end

    test "filters by label" do
      {:ok, _} = MemoryStore.create_block(%{label: "persona"})
      {:ok, _} = MemoryStore.create_block(%{label: "human"})

      assert {:ok, [block]} = MemoryStore.list_blocks(label: "human")
      assert block.label == "human"
    end

    test "is empty to begin with" do
      assert {:ok, []} = MemoryStore.list_blocks()
    end
  end

  describe "delete_block/1" do
    test "removes the block" do
      {:ok, block} = MemoryStore.create_block(%{label: "persona"})

      assert :ok = MemoryStore.delete_block(block.id)
      assert {:error, :not_found} = MemoryStore.get_block(block.id)
    end

    test "detaches it from every agent holding it" do
      {:ok, shared} = MemoryStore.create_block(%{label: "org", value: "Acme"})
      {:ok, _} = MemoryStore.create_agent("a", [], [shared.id])
      {:ok, _} = MemoryStore.create_agent("b", [], [shared.id])

      assert :ok = MemoryStore.delete_block(shared.id)

      assert {:ok, %{block_ids: []}} = MemoryStore.get_agent("a")
      assert {:ok, %{block_ids: []}} = MemoryStore.get_agent("b")
    end

    test "the detach survives a restart" do
      {:ok, shared} = MemoryStore.create_block(%{label: "org"})
      {:ok, _} = MemoryStore.create_agent("a", [], [shared.id])

      :ok = MemoryStore.delete_block(shared.id)
      restart_store()

      assert {:ok, %{block_ids: []}} = MemoryStore.get_agent("a")
    end

    test "is idempotent" do
      {:ok, block} = MemoryStore.create_block(%{label: "persona"})

      assert :ok = MemoryStore.delete_block(block.id)
      assert :ok = MemoryStore.delete_block(block.id)
    end
  end

  describe "read_only blocks" do
    test "cannot be written through the agent tools" do
      {:ok, _} =
        MemoryStore.create_agent("scout", [
          %{label: "rules", value: "immutable", read_only: true}
        ])

      assert {:error, :read_only} = MemoryStore.memory_rethink("scout", "rules", "changed")
      assert {:error, :read_only} = MemoryStore.memory_replace("scout", "rules", "im", "X")
      assert {:error, :read_only} = MemoryStore.memory_insert("scout", "rules", 0, "X")
    end

    test "can still be written through update_block" do
      {:ok, block} = MemoryStore.create_block(%{label: "rules", read_only: true})

      assert {:ok, updated} = MemoryStore.update_block(block.id, %{value: "admin edit"})
      assert updated.value == "admin edit"
    end
  end
end
