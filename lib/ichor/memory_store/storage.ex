defmodule Ichor.MemoryStore.Storage do
  @moduledoc """
  All ETS-level operations for the memory store: blocks, agents, recall, and archival.

  Pure ETS mutations with no Signal emissions. Callers (MemoryStore GenServer) are
  responsible for emitting signals after successful mutations.
  """

  alias Ichor.MemoryStore.Persistence

  # ---------------------------------------------------------------------------
  # Table constants (inlined from former Tables module)
  # ---------------------------------------------------------------------------

  @blocks_table :letta_blocks
  @agents_table :letta_agents
  @recall_table :letta_recall
  @archival_table :letta_archival
  @default_block_limit 2000
  @recall_limit 200
  @archival_ets_limit 500
  @max_agents 100
  @max_blocks 1000

  @doc "ETS table name for memory blocks."
  @spec blocks_table() :: atom()
  def blocks_table, do: @blocks_table

  @doc "ETS table name for agent records."
  @spec agents_table() :: atom()
  def agents_table, do: @agents_table

  @doc "ETS table name for recall entries."
  @spec recall_table() :: atom()
  def recall_table, do: @recall_table

  @doc "ETS table name for archival entries."
  @spec archival_table() :: atom()
  def archival_table, do: @archival_table

  @doc "Default character limit for a memory block."
  @spec default_block_limit() :: pos_integer()
  def default_block_limit, do: @default_block_limit

  @doc "Maximum number of recall entries kept in ETS per agent."
  @spec recall_limit() :: pos_integer()
  def recall_limit, do: @recall_limit

  @doc "Maximum number of archival entries kept in ETS per agent."
  @spec archival_ets_limit() :: pos_integer()
  def archival_ets_limit, do: @archival_ets_limit

  @doc "Maximum number of agent records."
  @spec max_agents() :: pos_integer()
  def max_agents, do: @max_agents

  @doc "Maximum number of memory blocks."
  @spec max_blocks() :: pos_integer()
  def max_blocks, do: @max_blocks

  @doc "Root directory for persisted memory data."
  @spec data_dir() :: String.t()
  def data_dir, do: Path.expand("~/.ichor/memory")

  # ---------------------------------------------------------------------------
  # Block CRUD
  # ---------------------------------------------------------------------------

  @doc "True if the block store has reached the maximum allowed blocks."
  @spec max_blocks_reached?() :: boolean()
  def max_blocks_reached? do
    :ets.info(@blocks_table, :size) >= @max_blocks
  end

  @doc "Look up a block by id."
  @spec get_block(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_block(block_id) do
    case :ets.lookup(@blocks_table, block_id) do
      [{^block_id, block}] -> {:ok, block}
      [] -> {:error, :not_found}
    end
  end

  @doc "Return all blocks, optionally filtered by label."
  @spec list_blocks(keyword()) :: [map()]
  def list_blocks(opts \\ []) do
    label_filter = Keyword.get(opts, :label)

    @blocks_table
    |> :ets.tab2list()
    |> Enum.map(fn {_id, block} -> block end)
    |> then(fn blocks ->
      if label_filter, do: Enum.filter(blocks, &(&1.label == label_filter)), else: blocks
    end)
    |> Enum.sort_by(& &1.created_at)
  end

  @doc "Create a new block from attrs and insert it into ETS."
  @spec create_block(map()) :: {:ok, map()}
  def create_block(attrs) do
    block = build_block(attrs)
    :ets.insert(@blocks_table, {block.id, block})
    {:ok, block}
  end

  @doc "Create multiple blocks and return their ids along with the dirty set."
  @spec create_blocks([map()]) :: {[String.t()], MapSet.t()}
  def create_blocks(attrs_list) do
    Enum.map_reduce(attrs_list, MapSet.new(), fn attrs, dirty ->
      {:ok, block} = create_block(attrs)
      {block.id, MapSet.put(dirty, block.id)}
    end)
  end

  @doc "Apply field changes to a block and persist to ETS."
  @spec update_block(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_block(block_id, changes) do
    with {:ok, block} <- get_block(block_id) do
      updated =
        block
        |> maybe_put(changes, :value)
        |> maybe_put(changes, :description)
        |> maybe_put(changes, :limit)
        |> Map.put(:updated_at, now_iso())

      persist_block(updated)
    end
  end

  @doc "Save a new value to a block, returning an error if it exceeds the limit."
  @spec save_block_value(map(), String.t()) :: {:ok, map()} | {:error, :exceeds_limit}
  def save_block_value(block, new_value) do
    if String.length(new_value) > block.limit do
      {:error, :exceeds_limit}
    else
      updated = %{block | value: new_value, updated_at: now_iso()}
      persist_block(updated)
    end
  end

  @doc """
  Delete a block from ETS and remove it from all agent block_ids lists.
  Returns the list of agent names whose records were dirtied.

  Bug 3a fix: dirty affected agents so GenServer can flush them.
  """
  @spec delete_block(String.t()) :: {[String.t()], :ok}
  def delete_block(block_id) do
    :ets.delete(@blocks_table, block_id)

    dirtied =
      @agents_table
      |> :ets.tab2list()
      |> Enum.flat_map(fn {name, agent} ->
        if block_id in (agent.block_ids || []) do
          updated = %{agent | block_ids: List.delete(agent.block_ids, block_id)}
          :ets.insert(@agents_table, {name, updated})
          [name]
        else
          []
        end
      end)

    {dirtied, :ok}
  end

  @doc "Resolve a list of block ids to their block maps, skipping missing ones."
  @spec resolve_blocks([String.t()]) :: [map()]
  def resolve_blocks(block_ids) do
    block_ids
    |> Enum.reduce([], fn id, acc ->
      case :ets.lookup(@blocks_table, id) do
        [{^id, block}] -> [block | acc]
        [] -> acc
      end
    end)
    |> Enum.reverse()
  end

  @doc "Find a specific block by label for a named agent."
  @spec find_agent_block(String.t(), String.t()) ::
          {:ok, map()} | {:error, :block_not_found | :agent_not_found}
  def find_agent_block(agent_name, block_label) do
    case :ets.lookup(@agents_table, agent_name) do
      [{^agent_name, agent}] ->
        case Enum.find(resolve_blocks(agent.block_ids), &(&1.label == block_label)) do
          nil -> {:error, :block_not_found}
          block -> {:ok, block}
        end

      [] ->
        {:error, :agent_not_found}
    end
  end

  @doc "Check if a block is writable. Returns `:ok` or `{:error, :read_only}`."
  @spec writable?(map()) :: :ok | {:error, :read_only}
  def writable?(block) do
    if block.read_only, do: {:error, :read_only}, else: :ok
  end

  @doc "Compile blocks to a single memory XML string for injection into agent context."
  @spec compile_blocks([map()]) :: String.t()
  def compile_blocks(blocks), do: Enum.map_join(blocks, "\n\n", &compile_block/1)

  # ---------------------------------------------------------------------------
  # Agent CRUD
  # ---------------------------------------------------------------------------

  @doc "True if agent count has reached the maximum."
  @spec max_agents_reached?() :: boolean()
  def max_agents_reached? do
    :ets.info(@agents_table, :size) >= @max_agents
  end

  @doc "True if an agent with the given name already exists."
  @spec agent_exists?(String.t()) :: boolean()
  def agent_exists?(name) do
    :ets.lookup(@agents_table, name) != []
  end

  @doc "Insert an agent record into ETS and return it."
  @spec insert_agent(map()) :: {:ok, map()}
  def insert_agent(agent) do
    :ets.insert(@agents_table, {agent.name, agent})
    {:ok, agent}
  end

  @doc "Look up an agent by name."
  @spec get_agent(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_agent(name) do
    case :ets.lookup(@agents_table, name) do
      [{^name, agent}] -> {:ok, agent}
      [] -> {:error, :not_found}
    end
  end

  @doc "List all agents, sorted by created_at."
  @spec list_agents() :: [map()]
  def list_agents do
    @agents_table
    |> :ets.tab2list()
    |> Enum.map(fn {_name, agent} -> agent end)
    |> Enum.sort_by(& &1.created_at)
  end

  # ---------------------------------------------------------------------------
  # Recall operations
  # ---------------------------------------------------------------------------

  @doc "Return all recall entries for an agent, newest first."
  @spec get_recall(String.t()) :: [map()]
  def get_recall(agent_name) do
    case :ets.lookup(@recall_table, agent_name) do
      [{^agent_name, entries}] -> entries
      [] -> []
    end
  end

  @doc "Add a recall entry for an agent."
  @spec add_recall(String.t(), atom(), String.t(), map()) :: {:ok, map()}
  def add_recall(agent_name, role, content, metadata) do
    entry = %{
      id: generate_id(),
      role: role,
      content: content,
      metadata: metadata,
      timestamp: now_iso()
    }

    updated = [entry | get_recall(agent_name)] |> Enum.take(@recall_limit)
    :ets.insert(@recall_table, {agent_name, updated})
    {:ok, entry}
  end

  @doc "Full-text search recall entries by query string with pagination."
  @spec search_recall(String.t(), String.t(), keyword()) :: [map()]
  def search_recall(agent_name, query, opts) do
    limit = Keyword.get(opts, :limit, 10)
    page = Keyword.get(opts, :page, 0)
    query_down = String.downcase(query)

    get_recall(agent_name)
    |> Enum.filter(&String.contains?(String.downcase(&1.content), query_down))
    |> Enum.drop(page * limit)
    |> Enum.take(limit)
  end

  @doc "Return recall entries within an ISO timestamp range."
  @spec search_recall_by_date(String.t(), String.t(), String.t(), keyword()) :: [map()]
  def search_recall_by_date(agent_name, start_date, end_date, opts) do
    limit = Keyword.get(opts, :limit, 10)

    get_recall(agent_name)
    |> Enum.filter(fn entry ->
      entry.timestamp >= start_date && entry.timestamp <= end_date
    end)
    |> Enum.take(limit)
  end

  # ---------------------------------------------------------------------------
  # Archival operations
  # ---------------------------------------------------------------------------

  @doc "Return all archival entries for an agent from ETS."
  @spec get_archival(String.t()) :: [map()]
  def get_archival(agent_name) do
    case :ets.lookup(@archival_table, agent_name) do
      [{^agent_name, entries}] -> entries
      [] -> []
    end
  end

  @doc "Return the total count of archival entries, reading the JSONL file if ETS is at limit."
  @spec count_archival(String.t()) :: non_neg_integer()
  def count_archival(agent_name) do
    ets_entries = get_archival(agent_name)

    if length(ets_entries) >= @archival_ets_limit do
      archival_path = Path.join([data_dir(), "agents", agent_name, "archival.jsonl"])

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

  @doc "Insert a new archival passage for an agent."
  @spec insert_archival(String.t(), String.t(), [String.t()]) :: {:ok, map()}
  def insert_archival(agent_name, content, tags) do
    passage = %{
      id: generate_id(),
      content: content,
      tags: tags,
      timestamp: now_iso()
    }

    updated = [passage | get_archival(agent_name)] |> Enum.take(@archival_ets_limit)
    :ets.insert(@archival_table, {agent_name, updated})
    {:ok, passage}
  end

  @doc "Full-text search archival entries by query string, with optional tag filter and pagination."
  @spec search_archival(String.t(), String.t(), keyword()) :: [map()]
  def search_archival(agent_name, query, opts) do
    tags_filter = Keyword.get(opts, :tags, [])
    limit = Keyword.get(opts, :limit, 10)
    page = Keyword.get(opts, :page, 0)
    query_down = String.downcase(query)

    archival_for_search(agent_name)
    |> filter_by_tags(tags_filter)
    |> Enum.filter(&String.contains?(String.downcase(&1.content), query_down))
    |> Enum.drop(page * limit)
    |> Enum.take(limit)
  end

  @doc "Remove a passage by id from an agent's archival store."
  @spec delete_archival(String.t(), String.t()) :: :ok
  def delete_archival(agent_name, passage_id) do
    updated = Enum.reject(get_archival(agent_name), &(&1.id == passage_id))
    :ets.insert(@archival_table, {agent_name, updated})
    :ok
  end

  @doc "Return a paginated list of archival entries with total count."
  @spec list_archival(String.t(), keyword()) :: %{passages: [map()], total: non_neg_integer()}
  def list_archival(agent_name, opts) do
    archival = archival_for_search(agent_name)
    limit = Keyword.get(opts, :limit, 50)
    page = Keyword.get(opts, :page, 0)

    %{
      passages: archival |> Enum.drop(page * limit) |> Enum.take(limit),
      total: length(archival)
    }
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp archival_for_search(agent_name) do
    ets_entries = get_archival(agent_name)

    if length(ets_entries) >= @archival_ets_limit do
      archival_path = Path.join([data_dir(), "agents", agent_name, "archival.jsonl"])
      if File.exists?(archival_path), do: Persistence.load_jsonl(archival_path), else: ets_entries
    else
      ets_entries
    end
  end

  defp build_block(attrs) do
    %{
      id: generate_id(),
      label: attr(attrs, :label),
      description: attr(attrs, :description, ""),
      value: attr(attrs, :value, ""),
      limit: attr(attrs, :limit, @default_block_limit),
      read_only: attr(attrs, :read_only, false),
      created_at: now_iso(),
      updated_at: now_iso()
    }
  end

  defp attr(map, key, default \\ nil), do: map[key] || map[to_string(key)] || default

  defp maybe_put(map, changes, key) do
    str_key = to_string(key)

    cond do
      Map.has_key?(changes, key) -> Map.put(map, key, Map.get(changes, key))
      Map.has_key?(changes, str_key) -> Map.put(map, key, Map.get(changes, str_key))
      true -> map
    end
  end

  defp persist_block(updated) do
    if String.length(updated.value) > updated.limit do
      {:error, :exceeds_limit}
    else
      :ets.insert(@blocks_table, {updated.id, updated})
      {:ok, updated}
    end
  end

  defp compile_block(block) do
    header = "<memory_block label=\"#{block.label}\" read_only=\"#{block.read_only}\">"
    footer = "</memory_block>"
    desc = if block.description != "", do: "<!-- #{block.description} -->\n", else: ""
    "#{header}\n#{desc}#{block.value}\n#{footer}"
  end

  defp filter_by_tags(entries, []), do: entries

  defp filter_by_tags(entries, tags),
    do: Enum.filter(entries, fn entry -> Enum.any?(tags, &(&1 in (entry.tags || []))) end)

  defp generate_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  defp now_iso, do: DateTime.to_iso8601(DateTime.utc_now())
end
