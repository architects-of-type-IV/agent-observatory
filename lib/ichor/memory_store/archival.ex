defmodule Ichor.MemoryStore.Archival do
  @moduledoc """
  Archival memory operations for the memory store.
  """

  alias Ichor.MemoryStore.Broadcast
  alias Ichor.MemoryStore.Persistence
  alias Ichor.MemoryStore.Tables

  def get(agent_name) do
    case :ets.lookup(Tables.archival_table(), agent_name) do
      [{^agent_name, entries}] -> entries
      [] -> []
    end
  end

  def count(agent_name) do
    ets_entries = get(agent_name)

    if length(ets_entries) >= Tables.archival_ets_limit() do
      archival_path = Path.join([Tables.data_dir(), "agents", agent_name, "archival.jsonl"])

      if File.exists?(archival_path) do
        archival_path
        |> File.stream!()
        |> Stream.reject(&(String.trim(&1) == ""))
        |> Enum.count()
      else
        length(ets_entries)
      end
    else
      length(ets_entries)
    end
  end

  def for_search(agent_name) do
    ets_entries = get(agent_name)

    if length(ets_entries) >= Tables.archival_ets_limit() do
      archival_path = Path.join([Tables.data_dir(), "agents", agent_name, "archival.jsonl"])
      if File.exists?(archival_path), do: Persistence.load_jsonl(archival_path), else: ets_entries
    else
      ets_entries
    end
  end

  def insert(agent_name, content, tags) do
    passage = %{
      id: generate_id(),
      content: content,
      tags: tags,
      timestamp: now_iso()
    }

    updated = [passage | get(agent_name)] |> Enum.take(Tables.archival_ets_limit())
    :ets.insert(Tables.archival_table(), {agent_name, updated})
    Broadcast.agent_changed(agent_name, :archival_insert)
    {:ok, passage}
  end

  def search(agent_name, query, opts) do
    tags_filter = Keyword.get(opts, :tags, [])
    limit = Keyword.get(opts, :limit, 10)
    page = Keyword.get(opts, :page, 0)
    query_down = String.downcase(query)

    for_search(agent_name)
    |> filter_by_tags(tags_filter)
    |> Enum.filter(fn entry -> String.contains?(String.downcase(entry.content), query_down) end)
    |> Enum.drop(page * limit)
    |> Enum.take(limit)
  end

  def delete(agent_name, passage_id) do
    updated = Enum.reject(get(agent_name), fn entry -> entry.id == passage_id end)
    :ets.insert(Tables.archival_table(), {agent_name, updated})
    :ok
  end

  def list(agent_name, opts) do
    archival = for_search(agent_name)
    limit = Keyword.get(opts, :limit, 50)
    page = Keyword.get(opts, :page, 0)

    %{
      passages: archival |> Enum.drop(page * limit) |> Enum.take(limit),
      total: length(archival)
    }
  end

  def filter_by_tags(entries, []), do: entries

  def filter_by_tags(entries, tags),
    do: Enum.filter(entries, fn entry -> Enum.any?(tags, &(&1 in (entry.tags || []))) end)

  defp generate_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  defp now_iso, do: DateTime.to_iso8601(DateTime.utc_now())
end
