defmodule MemoryStore.Persistence do
  @moduledoc """
  Disk persistence for the memory store.

  ## Layout

      <data_dir>/
        blocks/<block_id>.json        one file per block; blocks are shared,
                                      so they do not live under an agent
        agents/<name>/agent.json      the agent record and its block ids
        agents/<name>/recall.jsonl    conversation history, oldest first
        agents/<name>/archival.jsonl  archival passages, oldest first

  ETS is the working copy; disk is written from it on a timer. JSONL files are
  ordered oldest-first so they read as an append log, while ETS keeps entries
  newest-first for cheap prepends — `load_agent/2` reverses between the two.

  Archival and recall files are rewritten in full rather than appended to, so a
  deleted passage actually disappears.
  """

  require Logger

  alias MemoryStore.Config
  alias MemoryStore.Storage

  @doc "Load every block and agent from the data directory into ETS."
  @spec load_from_disk() :: :ok
  def load_from_disk do
    dir = Config.data_dir()
    load_blocks_from_dir(Path.join(dir, "blocks"))
    load_agents_from_dir(Path.join(dir, "agents"))
    :ok
  end

  @doc """
  Parse a JSONL file into entry maps with atom keys.

  Unparseable lines are skipped rather than failing the load — a truncated last
  line from an interrupted write should not cost the whole file.
  """
  @spec load_jsonl(String.t()) :: [map()]
  def load_jsonl(path) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.map(&decode/1)
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Stream.map(fn {:ok, data} -> atomize_entry(data) end)
    |> Enum.to_list()
  end

  @doc """
  Write the dirty blocks and agents named in `state` out to disk.

  Failures are logged and swallowed: a flush is a background timer tick, and
  crashing the store over a transient disk error would lose the in-memory state
  that has not been written yet.
  """
  @spec flush_dirty(%{dirty_blocks: MapSet.t(), dirty_agents: MapSet.t()}) :: :ok
  def flush_dirty(state) do
    dir = Config.data_dir()
    flush_dirty_blocks(state, dir)
    flush_dirty_agents(state, dir)
    :ok
  rescue
    error ->
      Logger.warning("MemoryStore: flush failed: #{inspect(error)}")
      :ok
  end

  # Loading

  defp load_blocks_from_dir(blocks_dir) do
    with true <- File.dir?(blocks_dir),
         {:ok, files} <- File.ls(blocks_dir) do
      files
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.each(&load_block_file(Path.join(blocks_dir, &1)))
    else
      _ -> :ok
    end
  end

  defp load_agents_from_dir(agents_dir) do
    with true <- File.dir?(agents_dir),
         {:ok, entries} <- File.ls(agents_dir) do
      entries
      |> Enum.filter(&File.dir?(Path.join(agents_dir, &1)))
      |> Enum.each(&load_agent(&1, Path.join(agents_dir, &1)))
    else
      _ -> :ok
    end
  end

  defp load_block_file(path) do
    with {:ok, content} <- File.read(path),
         {:ok, data} <- decode(content) do
      block = %{
        id: data["id"],
        label: data["label"],
        description: data["description"] || "",
        value: data["value"] || "",
        limit: data["limit"] || Config.default_block_limit(),
        read_only: data["read_only"] || false,
        created_at: data["created_at"],
        updated_at: data["updated_at"]
      }

      :ets.insert(Storage.blocks_table(), {block.id, block})
    else
      _ -> Logger.warning("MemoryStore: failed to load block #{path}")
    end
  end

  defp load_agent(name, agent_dir) do
    load_agent_config(name, agent_dir)
    load_agent_log(agent_dir, "recall.jsonl", Storage.recall_table(), name, Config.recall_limit())

    load_agent_log(
      agent_dir,
      "archival.jsonl",
      Storage.archival_table(),
      name,
      Config.archival_ets_limit()
    )

    Logger.debug("MemoryStore: loaded agent #{name}")
  end

  defp load_agent_config(name, agent_dir) do
    path = Path.join(agent_dir, "agent.json")

    if File.exists?(path) do
      with {:ok, content} <- File.read(path),
           {:ok, data} <- decode(content) do
        agent = %{
          name: data["name"] || name,
          block_ids: data["block_ids"] || [],
          created_at: data["created_at"],
          updated_at: data["updated_at"]
        }

        :ets.insert(Storage.agents_table(), {name, agent})
      else
        _ -> Logger.warning("MemoryStore: corrupt agent.json for #{name}")
      end
    end
  end

  # JSONL is oldest-first on disk; ETS wants newest-first. Reverse, then take
  # the limit so the entries kept are the newest rather than the oldest.
  defp load_agent_log(agent_dir, file, table, name, limit) do
    path = Path.join(agent_dir, file)

    if File.exists?(path) do
      entries = path |> load_jsonl() |> Enum.reverse() |> Enum.take(limit)
      :ets.insert(table, {name, entries})
    end
  end

  # Flushing

  defp flush_dirty_blocks(state, dir) do
    if MapSet.size(state.dirty_blocks) > 0 do
      blocks_dir = Path.join(dir, "blocks")
      File.mkdir_p!(blocks_dir)
      Enum.each(state.dirty_blocks, &flush_block(&1, blocks_dir))
    end
  end

  defp flush_block(block_id, blocks_dir) do
    path = Path.join(blocks_dir, "#{block_id}.json")

    case :ets.lookup(Storage.blocks_table(), block_id) do
      [{^block_id, block}] -> File.write!(path, JSON.encode!(block))
      [] -> if File.exists?(path), do: File.rm(path)
    end
  end

  defp flush_dirty_agents(state, dir) do
    Enum.each(state.dirty_agents, fn agent_name ->
      agent_dir = Path.join([dir, "agents", agent_name])
      File.mkdir_p!(agent_dir)
      flush_agent_config(agent_name, agent_dir)
      flush_log(Storage.recall_table(), agent_name, Path.join(agent_dir, "recall.jsonl"))
      flush_log(Storage.archival_table(), agent_name, Path.join(agent_dir, "archival.jsonl"))
    end)
  end

  defp flush_agent_config(agent_name, agent_dir) do
    case :ets.lookup(Storage.agents_table(), agent_name) do
      [{^agent_name, agent}] ->
        File.write!(Path.join(agent_dir, "agent.json"), JSON.encode!(agent))

      [] ->
        :ok
    end
  end

  # Full rewrite, not append: entries deleted from ETS have to disappear from
  # disk too, or they come back on the next load. An emptied log removes the
  # file rather than leaving the last written copy behind.
  defp flush_log(table, agent_name, path) do
    entries =
      case :ets.lookup(table, agent_name) do
        [{^agent_name, entries}] -> entries
        [] -> []
      end

    if entries == [] do
      if File.exists?(path), do: File.rm(path)
    else
      lines = entries |> Enum.reverse() |> Enum.map_join("\n", &JSON.encode!/1)
      File.write!(path, lines <> "\n")
    end
  end

  defp decode(content) do
    {:ok, JSON.decode!(content)}
  rescue
    _ -> :error
  end

  defp atomize_entry(data) when is_map(data) do
    %{
      id: data["id"],
      role: data["role"],
      content: data["content"] || data["summary"],
      tags: data["tags"] || [],
      metadata: data["metadata"] || %{},
      timestamp: data["timestamp"]
    }
  end
end
