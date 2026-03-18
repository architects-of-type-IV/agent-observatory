defmodule Ichor.MemoryStore.RecallTest do
  use ExUnit.Case, async: false

  alias Ichor.MemoryStore.Recall
  alias Ichor.MemoryStore.Tables

  setup do
    ensure_table(Tables.recall_table())

    on_exit(fn ->
      delete_table(Tables.recall_table())
    end)

    :ok
  end

  test "adds recall entries and searches by content" do
    {:ok, _entry} = Recall.add("agent-1", "assistant", "alpha note", %{})
    {:ok, _entry} = Recall.add("agent-1", "user", "beta note", %{})

    results = Recall.search("agent-1", "beta", page: 0, limit: 10)

    assert length(results) == 1
    assert hd(results).content == "beta note"
  end

  defp ensure_table(name) do
    case :ets.info(name) do
      :undefined -> :ets.new(name, [:named_table, :public, :set])
      _ -> true
    end
  end

  defp delete_table(name) do
    case :ets.info(name) do
      :undefined -> :ok
      _ -> :ets.delete(name)
    end
  end
end
