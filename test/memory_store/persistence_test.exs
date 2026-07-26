defmodule MemoryStore.PersistenceTest do
  use MemoryStore.StoreCase

  describe "flush and reload" do
    test "blocks and agents survive a restart", %{data_dir: dir} do
      {:ok, _} =
        MemoryStore.create_agent("scout", [
          %{label: "persona", value: "I survey.", description: "role"}
        ])

      :ok = MemoryStore.flush()
      assert File.dir?(Path.join(dir, "blocks"))
      assert File.exists?(Path.join([dir, "agents", "scout", "agent.json"]))

      restart_store()

      assert {:ok, core} = MemoryStore.read_core_memory("scout")
      assert [%{label: "persona", value: "I survey.", description: "role"}] = core.blocks
    end

    test "block limit and read_only survive a restart" do
      {:ok, _} =
        MemoryStore.create_agent("scout", [
          %{label: "rules", value: "v", limit: 42, read_only: true}
        ])

      :ok = MemoryStore.flush()
      restart_store()

      assert {:ok, [block]} = MemoryStore.list_blocks(label: "rules")
      assert block.limit == 42
      assert block.read_only == true
    end

    test "recall survives a restart, newest first" do
      {:ok, _} = MemoryStore.create_agent("scout")
      for n <- 1..3, do: MemoryStore.add_recall("scout", :user, "item #{n}")

      :ok = MemoryStore.flush()
      restart_store()

      assert {:ok, results} = MemoryStore.conversation_search("scout", "item", limit: 10)
      assert Enum.map(results, & &1.content) == ["item 3", "item 2", "item 1"]
    end

    test "archival survives a restart, newest first" do
      {:ok, _} = MemoryStore.create_agent("scout")
      for n <- 1..3, do: MemoryStore.archival_memory_insert("scout", "passage #{n}", ["t"])

      :ok = MemoryStore.flush()
      restart_store()

      assert {:ok, %{passages: passages, total: 3}} = MemoryStore.archival_memory_list("scout")
      assert Enum.map(passages, & &1.content) == ["passage 3", "passage 2", "passage 1"]
      assert hd(passages).tags == ["t"]
    end

    test "a deleted passage does not come back after a restart" do
      {:ok, _} = MemoryStore.create_agent("scout")
      {:ok, keep} = MemoryStore.archival_memory_insert("scout", "keep me")
      {:ok, drop} = MemoryStore.archival_memory_insert("scout", "drop me")
      :ok = MemoryStore.flush()

      :ok = MemoryStore.archival_memory_delete("scout", drop.id)
      :ok = MemoryStore.flush()
      restart_store()

      assert {:ok, %{passages: [passage], total: 1}} = MemoryStore.archival_memory_list("scout")
      assert passage.id == keep.id
    end

    test "emptying archival clears the file rather than leaving stale entries", %{data_dir: dir} do
      {:ok, _} = MemoryStore.create_agent("scout")
      {:ok, passage} = MemoryStore.archival_memory_insert("scout", "only one")
      :ok = MemoryStore.flush()

      path = Path.join([dir, "agents", "scout", "archival.jsonl"])
      assert File.exists?(path)

      :ok = MemoryStore.archival_memory_delete("scout", passage.id)
      :ok = MemoryStore.flush()

      refute File.exists?(path)

      restart_store()
      assert {:ok, %{total: 0}} = MemoryStore.archival_memory_list("scout")
    end

    test "a deleted block's file is removed", %{data_dir: dir} do
      {:ok, block} = MemoryStore.create_block(%{label: "persona"})
      :ok = MemoryStore.flush()

      path = Path.join([dir, "blocks", "#{block.id}.json"])
      assert File.exists?(path)

      :ok = MemoryStore.delete_block(block.id)
      :ok = MemoryStore.flush()

      refute File.exists?(path)
    end

    test "terminate flushes on a clean shutdown" do
      {:ok, _} = MemoryStore.create_agent("scout", [%{label: "persona", value: "unflushed"}])

      # No explicit flush — the restart's shutdown has to persist this.
      restart_store()

      assert {:ok, core} = MemoryStore.read_core_memory("scout")
      assert [%{value: "unflushed"}] = core.blocks
    end

    test "only dirty records are rewritten", %{data_dir: dir} do
      {:ok, _} = MemoryStore.create_agent("a", [%{label: "one", value: "1"}])
      :ok = MemoryStore.flush()

      agent_a = Path.join([dir, "agents", "a", "agent.json"])
      before = File.stat!(agent_a).mtime

      {:ok, _} = MemoryStore.create_agent("b", [%{label: "two", value: "2"}])
      :ok = MemoryStore.flush()

      assert File.stat!(agent_a).mtime == before
      assert File.exists?(Path.join([dir, "agents", "b", "agent.json"]))
    end
  end

  describe "corrupt data on disk" do
    test "a malformed JSONL line is skipped, the rest load", %{data_dir: dir} do
      {:ok, _} = MemoryStore.create_agent("scout")
      {:ok, _} = MemoryStore.archival_memory_insert("scout", "good one")
      :ok = MemoryStore.flush()

      path = Path.join([dir, "agents", "scout", "archival.jsonl"])
      File.write!(path, File.read!(path) <> "{not json\n")

      restart_store()

      assert {:ok, %{total: 1}} = MemoryStore.archival_memory_list("scout")
    end

    test "a corrupt block file is skipped rather than crashing the load", %{data_dir: dir} do
      {:ok, _} = MemoryStore.create_agent("scout", [%{label: "good", value: "v"}])
      :ok = MemoryStore.flush()

      File.write!(Path.join([dir, "blocks", "corrupt.json"]), "{not json")

      restart_store()

      assert {:ok, [block]} = MemoryStore.list_blocks()
      assert block.label == "good"
    end

    test "a corrupt agent.json leaves the other agents loadable", %{data_dir: dir} do
      {:ok, _} = MemoryStore.create_agent("good")
      {:ok, _} = MemoryStore.create_agent("bad")
      :ok = MemoryStore.flush()

      File.write!(Path.join([dir, "agents", "bad", "agent.json"]), "{not json")

      restart_store()

      assert {:ok, _} = MemoryStore.get_agent("good")
      assert {:error, :not_found} = MemoryStore.get_agent("bad")
    end

    test "an empty data directory starts clean" do
      assert {:ok, []} = MemoryStore.list_agents()
      assert {:ok, []} = MemoryStore.list_blocks()
    end
  end

  describe "data_dir/0" do
    test "reports the configured directory", %{data_dir: dir} do
      assert MemoryStore.data_dir() == Path.expand(dir)
    end
  end
end
