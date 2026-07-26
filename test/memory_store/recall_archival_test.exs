defmodule MemoryStore.RecallArchivalTest do
  use MemoryStore.StoreCase

  setup do
    {:ok, _} = MemoryStore.create_agent("scout")
    :ok
  end

  describe "recall memory" do
    test "add_recall returns the stored entry" do
      assert {:ok, entry} = MemoryStore.add_recall("scout", :user, "hello there", %{turn: 1})

      assert entry.role == :user
      assert entry.content == "hello there"
      assert entry.metadata == %{turn: 1}
      assert is_binary(entry.id)
      assert is_binary(entry.timestamp)
    end

    test "conversation_search matches case-insensitively" do
      {:ok, _} = MemoryStore.add_recall("scout", :user, "Deploy the Service")

      assert {:ok, [hit]} = MemoryStore.conversation_search("scout", "deploy the service")
      assert hit.content == "Deploy the Service"
    end

    test "conversation_search matches substrings" do
      {:ok, _} = MemoryStore.add_recall("scout", :user, "the quick brown fox")

      assert {:ok, [_]} = MemoryStore.conversation_search("scout", "quick brown")
    end

    test "conversation_search returns newest first" do
      {:ok, _} = MemoryStore.add_recall("scout", :user, "match one")
      {:ok, _} = MemoryStore.add_recall("scout", :user, "match two")

      assert {:ok, [first, second]} = MemoryStore.conversation_search("scout", "match")
      assert first.content == "match two"
      assert second.content == "match one"
    end

    test "conversation_search paginates" do
      for n <- 1..5, do: MemoryStore.add_recall("scout", :user, "item #{n}")

      assert {:ok, page0} = MemoryStore.conversation_search("scout", "item", limit: 2, page: 0)
      assert {:ok, page1} = MemoryStore.conversation_search("scout", "item", limit: 2, page: 1)

      assert length(page0) == 2
      assert length(page1) == 2
      assert Enum.map(page0, & &1.id) != Enum.map(page1, & &1.id)
    end

    test "conversation_search returns nothing for a miss" do
      {:ok, _} = MemoryStore.add_recall("scout", :user, "hello")

      assert {:ok, []} = MemoryStore.conversation_search("scout", "goodbye")
    end

    test "conversation_search on an unknown agent is empty, not an error" do
      assert {:ok, []} = MemoryStore.conversation_search("ghost", "anything")
    end

    test "conversation_search_date accepts DateTime bounds" do
      {:ok, _} = MemoryStore.add_recall("scout", :user, "in range")

      from = DateTime.add(DateTime.utc_now(), -60, :second)
      to = DateTime.add(DateTime.utc_now(), 60, :second)

      assert {:ok, [entry]} = MemoryStore.conversation_search_date("scout", from, to)
      assert entry.content == "in range"
    end

    test "conversation_search_date accepts ISO strings" do
      {:ok, _} = MemoryStore.add_recall("scout", :user, "in range")

      from = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.to_iso8601()
      to = DateTime.utc_now() |> DateTime.add(60, :second) |> DateTime.to_iso8601()

      assert {:ok, [_]} = MemoryStore.conversation_search_date("scout", from, to)
    end

    test "conversation_search_date excludes entries outside the window" do
      {:ok, _} = MemoryStore.add_recall("scout", :user, "now")

      from = DateTime.add(DateTime.utc_now(), -7200, :second)
      to = DateTime.add(DateTime.utc_now(), -3600, :second)

      assert {:ok, []} = MemoryStore.conversation_search_date("scout", from, to)
    end

    @tag recall_limit: 3
    test "older entries age out of ETS at the recall limit" do
      for n <- 1..5, do: MemoryStore.add_recall("scout", :user, "item #{n}")

      assert {:ok, results} = MemoryStore.conversation_search("scout", "item", limit: 100)
      assert length(results) == 3
      assert Enum.map(results, & &1.content) == ["item 5", "item 4", "item 3"]
    end
  end

  describe "archival memory" do
    test "insert returns the stored passage" do
      assert {:ok, passage} =
               MemoryStore.archival_memory_insert("scout", "Repo uses Ash.", ["stack"])

      assert passage.content == "Repo uses Ash."
      assert passage.tags == ["stack"]
      assert is_binary(passage.id)
    end

    test "tags default to empty" do
      assert {:ok, passage} = MemoryStore.archival_memory_insert("scout", "no tags")
      assert passage.tags == []
    end

    test "search matches case-insensitively" do
      {:ok, _} = MemoryStore.archival_memory_insert("scout", "Uses PostgreSQL")

      assert {:ok, [hit]} = MemoryStore.archival_memory_search("scout", "postgresql")
      assert hit.content == "Uses PostgreSQL"
    end

    test "search filters by tag" do
      {:ok, _} = MemoryStore.archival_memory_insert("scout", "fact one", ["stack"])
      {:ok, _} = MemoryStore.archival_memory_insert("scout", "fact two", ["people"])

      assert {:ok, [hit]} = MemoryStore.archival_memory_search("scout", "fact", tags: ["people"])
      assert hit.content == "fact two"
    end

    test "search with several tags matches any of them" do
      {:ok, _} = MemoryStore.archival_memory_insert("scout", "fact one", ["stack"])
      {:ok, _} = MemoryStore.archival_memory_insert("scout", "fact two", ["people"])
      {:ok, _} = MemoryStore.archival_memory_insert("scout", "fact three", ["other"])

      assert {:ok, hits} =
               MemoryStore.archival_memory_search("scout", "fact", tags: ["stack", "people"])

      assert length(hits) == 2
    end

    test "search paginates" do
      for n <- 1..5, do: MemoryStore.archival_memory_insert("scout", "passage #{n}")

      assert {:ok, page0} = MemoryStore.archival_memory_search("scout", "passage", limit: 2)

      assert {:ok, page1} =
               MemoryStore.archival_memory_search("scout", "passage", limit: 2, page: 1)

      assert length(page0) == 2
      assert Enum.map(page0, & &1.id) != Enum.map(page1, & &1.id)
    end

    test "list returns a page and the total" do
      for n <- 1..5, do: MemoryStore.archival_memory_insert("scout", "passage #{n}")

      assert {:ok, %{passages: passages, total: 5}} =
               MemoryStore.archival_memory_list("scout", limit: 2)

      assert length(passages) == 2
    end

    test "delete removes the passage" do
      {:ok, passage} = MemoryStore.archival_memory_insert("scout", "temporary")

      assert :ok = MemoryStore.archival_memory_delete("scout", passage.id)
      assert {:ok, %{total: 0}} = MemoryStore.archival_memory_list("scout")
    end

    test "delete of an unknown id is a no-op" do
      {:ok, _} = MemoryStore.archival_memory_insert("scout", "kept")

      assert :ok = MemoryStore.archival_memory_delete("scout", "nope")
      assert {:ok, %{total: 1}} = MemoryStore.archival_memory_list("scout")
    end

    @tag archival_ets_limit: 3
    test "search falls back to disk once ETS is at capacity" do
      for n <- 1..3, do: MemoryStore.archival_memory_insert("scout", "passage #{n}")
      :ok = MemoryStore.flush()

      # ETS is now full, so search reads the JSONL file rather than ETS alone.
      assert {:ok, hits} = MemoryStore.archival_memory_search("scout", "passage", limit: 100)
      assert length(hits) == 3
    end

    @tag archival_ets_limit: 2
    test "count reflects the file, not just the ETS window" do
      for n <- 1..2, do: MemoryStore.archival_memory_insert("scout", "passage #{n}")
      :ok = MemoryStore.flush()

      assert {:ok, [agent]} = MemoryStore.list_agents()
      assert agent.archival_count == 2
    end
  end
end
