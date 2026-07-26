defmodule MemoryStore.MemoryToolsTest do
  use MemoryStore.StoreCase

  setup do
    {:ok, _} =
      MemoryStore.create_agent("scout", [
        %{label: "human", value: "line one\nline two\nline three"}
      ])

    :ok
  end

  defp value(label \\ "human") do
    {:ok, core} = MemoryStore.read_core_memory("scout")
    Enum.find(core.blocks, &(&1.label == label)).value
  end

  describe "memory_replace/4" do
    test "replaces the first occurrence only" do
      {:ok, _} = MemoryStore.memory_rethink("scout", "human", "aa bb aa")

      assert {:ok, _} = MemoryStore.memory_replace("scout", "human", "aa", "zz")
      assert value() == "zz bb aa"
    end

    test "reports text that is not there" do
      assert {:error, :text_not_found} =
               MemoryStore.memory_replace("scout", "human", "absent", "x")

      assert value() == "line one\nline two\nline three"
    end

    test "reports a missing block label" do
      assert {:error, :block_not_found} = MemoryStore.memory_replace("scout", "nope", "a", "b")
    end

    test "reports a missing agent" do
      assert {:error, :agent_not_found} = MemoryStore.memory_replace("ghost", "human", "a", "b")
    end

    test "refuses a replacement past the block limit" do
      {:ok, block} = MemoryStore.create_block(%{label: "tiny", value: "ab", limit: 3})
      {:ok, _} = MemoryStore.attach_block("scout", block.id)

      assert {:error, :exceeds_limit} =
               MemoryStore.memory_replace("scout", "tiny", "ab", "abcdef")
    end
  end

  describe "memory_insert/4" do
    test "inserts at the top" do
      assert {:ok, _} = MemoryStore.memory_insert("scout", "human", 0, "line zero")
      assert value() == "line zero\nline one\nline two\nline three"
    end

    test "inserts in the middle" do
      assert {:ok, _} = MemoryStore.memory_insert("scout", "human", 1, "inserted")
      assert value() == "line one\ninserted\nline two\nline three"
    end

    test "appends at the end" do
      assert {:ok, _} = MemoryStore.memory_insert("scout", "human", 3, "line four")
      assert value() == "line one\nline two\nline three\nline four"
    end

    test "clamps a position past the end to an append" do
      assert {:ok, _} = MemoryStore.memory_insert("scout", "human", 999, "last")
      assert value() == "line one\nline two\nline three\nlast"
    end

    test "clamps a negative position to the top" do
      assert {:ok, _} = MemoryStore.memory_insert("scout", "human", -5, "first")
      assert value() == "first\nline one\nline two\nline three"
    end

    test "refuses an insert past the block limit" do
      {:ok, block} = MemoryStore.create_block(%{label: "tiny", value: "ab", limit: 3})
      {:ok, _} = MemoryStore.attach_block("scout", block.id)

      assert {:error, :exceeds_limit} = MemoryStore.memory_insert("scout", "tiny", 0, "toolong")
    end
  end

  describe "memory_rethink/3" do
    test "replaces the whole value" do
      assert {:ok, updated} = MemoryStore.memory_rethink("scout", "human", "entirely new")

      assert updated.value == "entirely new"
      assert value() == "entirely new"
    end

    test "bumps updated_at" do
      {:ok, before} = MemoryStore.list_blocks(label: "human")
      before = hd(before)

      {:ok, updated} = MemoryStore.memory_rethink("scout", "human", "new")

      assert updated.updated_at >= before.updated_at
    end

    test "refuses a value past the block limit" do
      {:ok, block} = MemoryStore.create_block(%{label: "tiny", value: "", limit: 3})
      {:ok, _} = MemoryStore.attach_block("scout", block.id)

      assert {:error, :exceeds_limit} = MemoryStore.memory_rethink("scout", "tiny", "toolong")
    end

    test "allows a value exactly at the limit" do
      {:ok, block} = MemoryStore.create_block(%{label: "tiny", value: "", limit: 3})
      {:ok, _} = MemoryStore.attach_block("scout", block.id)

      assert {:ok, updated} = MemoryStore.memory_rethink("scout", "tiny", "abc")
      assert updated.value == "abc"
    end
  end
end
