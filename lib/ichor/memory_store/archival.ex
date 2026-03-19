defmodule Ichor.MemoryStore.Archival do
  @moduledoc """
  Archival memory operations for the memory store.
  """

  alias Ichor.MemoryStore.Persistence
  alias Ichor.MemoryStore.Tables

  @doc "Return all archival entries for an agent from ETS."
  @spec get(String.t()) :: [map()]
  def get(agent_name) do
    case :ets.lookup(Tables.archival_table(), agent_name) do
      [{^agent_name, entries}] -> entries
      [] -> []
    end
  end

  @doc "Return the total count of archival entries, reading the JSONL file if ETS is at limit."
  @spec count(String.t()) :: non_neg_integer()
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

  defp for_search(agent_name) do
    ets_entries = get(agent_name)

    if length(ets_entries) >= Tables.archival_ets_limit() do
      archival_path = Path.join([Tables.data_dir(), "agents", agent_name, "archival.jsonl"])
      if File.exists?(archival_path), do: Persistence.load_jsonl(archival_path), else: ets_entries
    else
      ets_entries
    end
  end

  @doc "Insert a new archival passage for an agent."
  @spec insert(String.t(), String.t(), [String.t()]) :: {:ok, map()}
  def insert(agent_name, content, tags) do
    passage = %{
      id: generate_id(),
      content: content,
      tags: tags,
      timestamp: now_iso()
    }

    updated = [passage | get(agent_name)] |> Enum.take(Tables.archival_ets_limit())
    :ets.insert(Tables.archival_table(), {agent_name, updated})

    Ichor.Signals.emit(:memory_changed, agent_name, %{
      agent_name: agent_name,
      event: :archival_insert
    })

    {:ok, passage}
  end

  @doc "Full-text search archival entries by query string, with optional tag filter and pagination."
  @spec search(String.t(), String.t(), keyword()) :: [map()]
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

  @doc "Remove a passage by id from an agent's archival store."
  @spec delete(String.t(), String.t()) :: :ok
  def delete(agent_name, passage_id) do
    updated = Enum.reject(get(agent_name), fn entry -> entry.id == passage_id end)
    :ets.insert(Tables.archival_table(), {agent_name, updated})
    :ok
  end

  @doc "Return a paginated list of archival entries with total count."
  @spec list(String.t(), keyword()) :: %{passages: [map()], total: non_neg_integer()}
  def list(agent_name, opts) do
    archival = for_search(agent_name)
    limit = Keyword.get(opts, :limit, 50)
    page = Keyword.get(opts, :page, 0)

    %{
      passages: archival |> Enum.drop(page * limit) |> Enum.take(limit),
      total: length(archival)
    }
  end

  defp filter_by_tags(entries, []), do: entries

  defp filter_by_tags(entries, tags),
    do: Enum.filter(entries, fn entry -> Enum.any?(tags, &(&1 in (entry.tags || []))) end)

  defp generate_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  defp now_iso, do: DateTime.to_iso8601(DateTime.utc_now())
end
