defmodule Ichor.MemoryStore.Recall do
  @moduledoc """
  Recall memory operations for the memory store.
  """

  alias Ichor.MemoryStore.Tables

  def get(agent_name) do
    case :ets.lookup(Tables.recall_table(), agent_name) do
      [{^agent_name, entries}] -> entries
      [] -> []
    end
  end

  def add(agent_name, role, content, metadata) do
    entry = %{
      id: generate_id(),
      role: role,
      content: content,
      metadata: metadata,
      timestamp: now_iso()
    }

    updated = [entry | get(agent_name)] |> Enum.take(Tables.recall_limit())
    :ets.insert(Tables.recall_table(), {agent_name, updated})
    {:ok, entry}
  end

  def search(agent_name, query, opts) do
    limit = Keyword.get(opts, :limit, 10)
    page = Keyword.get(opts, :page, 0)
    query_down = String.downcase(query)

    get(agent_name)
    |> Enum.filter(fn entry -> String.contains?(String.downcase(entry.content), query_down) end)
    |> Enum.drop(page * limit)
    |> Enum.take(limit)
  end

  def search_by_date(agent_name, start_date, end_date, opts) do
    limit = Keyword.get(opts, :limit, 10)

    get(agent_name)
    |> Enum.filter(fn entry ->
      timestamp = entry.timestamp
      timestamp >= start_date && timestamp <= end_date
    end)
    |> Enum.take(limit)
  end

  defp generate_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  defp now_iso, do: DateTime.to_iso8601(DateTime.utc_now())
end
