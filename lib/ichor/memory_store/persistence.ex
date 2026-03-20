defmodule Ichor.MemoryStore.Persistence do
  @moduledoc """
  Disk persistence for the memory store.
  """

  require Logger

  alias Ichor.MemoryStore.Storage

  @doc "Load all blocks and agents from the configured data directory into ETS."
  @spec load_from_disk() :: :ok
  def load_from_disk do
    dir = Storage.data_dir()
    load_blocks_from_dir(Path.join(dir, "blocks"))
    load_agents_from_dir(Path.join(dir, "agents"))
  end

  @doc "Parse a JSONL file into a list of atomized entry maps."
  @spec load_jsonl(String.t()) :: [map()]
  def load_jsonl(path) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.map(&Jason.decode/1)
    |> Stream.filter(fn
      {:ok, _} -> true
      _ -> false
    end)
    |> Stream.map(fn {:ok, data} -> atomize_entry(data) end)
    |> Enum.to_list()
  end

  @doc "Flush dirty blocks and agents from state to disk."
  @spec flush_dirty(map()) :: :ok
  def flush_dirty(state) do
    dir = Storage.data_dir()
    flush_dirty_blocks(state, dir)
    flush_dirty_agents(state, dir)
  rescue
    error -> Logger.warning("MemoryStore: flush failed: #{inspect(error)}")
  end

  defp load_blocks_from_dir(blocks_dir) do
    with true <- File.dir?(blocks_dir),
         {:ok, files} <- File.ls(blocks_dir) do
      files
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.each(fn file -> load_block_file(Path.join(blocks_dir, file)) end)
    else
      _ -> :ok
    end
  end

  defp load_agents_from_dir(agents_dir) do
    with true <- File.dir?(agents_dir),
         {:ok, entries} <- File.ls(agents_dir) do
      entries
      |> Enum.filter(&File.dir?(Path.join(agents_dir, &1)))
      |> Enum.each(fn name -> load_agent_from_disk(name, Path.join(agents_dir, name)) end)
    else
      _ -> :ok
    end
  end

  defp load_block_file(path) do
    with {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content) do
      block = %{
        id: data["id"],
        label: data["label"],
        description: data["description"] || "",
        value: data["value"] || "",
        limit: data["limit"] || Storage.default_block_limit(),
        read_only: data["read_only"] || false,
        created_at: data["created_at"],
        updated_at: data["updated_at"]
      }

      :ets.insert(Storage.blocks_table(), {block.id, block})
    else
      _ -> Logger.warning("MemoryStore: failed to load block #{path}")
    end
  end

  defp load_agent_from_disk(name, agent_dir) do
    config_path = Path.join(agent_dir, "agent.json")

    if File.exists?(config_path) do
      with {:ok, content} <- File.read(config_path),
           {:ok, data} <- Jason.decode(content) do
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

    recall_path = Path.join(agent_dir, "recall.jsonl")

    if File.exists?(recall_path) do
      # Bug 3c fix: JSONL is written oldest-first (reversed at flush). Loading
      # reverses back so the newest entry sits at the head, matching runtime
      # insert order where [newest | rest].
      entries =
        recall_path
        |> load_jsonl()
        |> Enum.reverse()
        |> Enum.take(Storage.recall_limit())

      :ets.insert(Storage.recall_table(), {name, entries})
    end

    archival_path = Path.join(agent_dir, "archival.jsonl")

    if File.exists?(archival_path) do
      # Bug 3c fix: same reversal for archival -- newest first in ETS.
      entries =
        archival_path
        |> load_jsonl()
        |> Enum.reverse()
        |> Enum.take(Storage.archival_ets_limit())

      :ets.insert(Storage.archival_table(), {name, entries})
    end

    Logger.debug("MemoryStore: loaded agent #{name}")
  end

  defp flush_dirty_blocks(state, dir) do
    if MapSet.size(state.dirty_blocks) > 0 do
      blocks_dir = Path.join(dir, "blocks")
      File.mkdir_p!(blocks_dir)
      Enum.each(state.dirty_blocks, &flush_single_block(&1, blocks_dir))
    end
  end

  defp flush_single_block(block_id, blocks_dir) do
    path = Path.join(blocks_dir, "#{block_id}.json")

    case :ets.lookup(Storage.blocks_table(), block_id) do
      [{^block_id, block}] -> File.write!(path, Jason.encode!(block, pretty: true))
      [] -> if File.exists?(path), do: File.rm(path)
    end
  end

  defp flush_dirty_agents(state, dir) do
    Enum.each(state.dirty_agents, fn agent_name ->
      agent_dir = Path.join([dir, "agents", agent_name])
      File.mkdir_p!(agent_dir)
      flush_agent_config(agent_name, agent_dir)
      flush_agent_recall(agent_name, agent_dir)
      flush_agent_archival(agent_name, agent_dir)
    end)
  end

  defp flush_agent_config(agent_name, agent_dir) do
    case :ets.lookup(Storage.agents_table(), agent_name) do
      [{^agent_name, agent}] ->
        File.write!(Path.join(agent_dir, "agent.json"), Jason.encode!(agent, pretty: true))

      [] ->
        :ok
    end
  end

  defp flush_agent_recall(agent_name, agent_dir) do
    recall =
      case :ets.lookup(Storage.recall_table(), agent_name) do
        [{^agent_name, entries}] -> entries
        [] -> []
      end

    if recall != [] do
      # ETS stores newest-first; write oldest-first to JSONL so load order is
      # oldest → newest, matching chronological append convention.
      lines = recall |> Enum.reverse() |> Enum.map_join("\n", &Jason.encode!/1)
      File.write!(Path.join(agent_dir, "recall.jsonl"), lines <> "\n")
    end
  end

  defp flush_agent_archival(agent_name, agent_dir) do
    archival =
      case :ets.lookup(Storage.archival_table(), agent_name) do
        [{^agent_name, entries}] -> entries
        [] -> []
      end

    # Bug 3b fix: full rewrite of current ETS state rather than append-only.
    # Deleted passages would otherwise remain in the JSONL file indefinitely.
    if archival != [] do
      archival_path = Path.join(agent_dir, "archival.jsonl")
      lines = archival |> Enum.reverse() |> Enum.map_join("\n", &Jason.encode!/1)
      File.write!(archival_path, lines <> "\n")
    end
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
