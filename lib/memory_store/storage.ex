defmodule MemoryStore.Storage do
  @moduledoc """
  Every ETS-level operation for the store: blocks, agents, recall, and archival.

  Pure ETS mutation with no notifications. The `MemoryStore` process owns the
  tables and is responsible for notifying after a successful mutation, which
  keeps this module free to be called from tests and tooling without side
  effects leaking out.
  """

  alias MemoryStore.Config
  alias MemoryStore.Persistence

  @blocks_table :memory_store_blocks
  @agents_table :memory_store_agents
  @recall_table :memory_store_recall
  @archival_table :memory_store_archival

  @typedoc "A core memory block."
  @type block :: %{
          id: String.t(),
          label: String.t(),
          description: String.t(),
          value: String.t(),
          limit: pos_integer(),
          read_only: boolean(),
          created_at: String.t(),
          updated_at: String.t()
        }

  @typedoc "An agent record; `block_ids` is ordered."
  @type agent :: %{
          name: String.t(),
          block_ids: [String.t()],
          created_at: String.t(),
          updated_at: String.t()
        }

  @doc "ETS table holding memory blocks."
  @spec blocks_table() :: atom()
  def blocks_table, do: @blocks_table

  @doc "ETS table holding agent records."
  @spec agents_table() :: atom()
  def agents_table, do: @agents_table

  @doc "ETS table holding recall entries, keyed by agent name."
  @spec recall_table() :: atom()
  def recall_table, do: @recall_table

  @doc "ETS table holding archival entries, keyed by agent name."
  @spec archival_table() :: atom()
  def archival_table, do: @archival_table

  @doc "All four ETS table names."
  @spec tables() :: [atom()]
  def tables, do: [@blocks_table, @agents_table, @recall_table, @archival_table]

  @doc "Root directory for persisted memory."
  @spec data_dir() :: String.t()
  def data_dir, do: Config.data_dir()

  # Blocks

  @doc "Whether the block count has reached `MemoryStore.Config.max_blocks/0`."
  @spec max_blocks_reached?() :: boolean()
  def max_blocks_reached?, do: :ets.info(@blocks_table, :size) >= Config.max_blocks()

  @doc "Look up a block by id."
  @spec get_block(String.t()) :: {:ok, block()} | {:error, :not_found}
  def get_block(block_id) do
    case :ets.lookup(@blocks_table, block_id) do
      [{^block_id, block}] -> {:ok, block}
      [] -> {:error, :not_found}
    end
  end

  @doc "All blocks, oldest first, optionally filtered to one `:label`."
  @spec list_blocks(keyword()) :: [block()]
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

  @doc "Build a block from attrs and insert it."
  @spec create_block(map()) :: {:ok, block()}
  def create_block(attrs) do
    block = build_block(attrs)
    :ets.insert(@blocks_table, {block.id, block})
    {:ok, block}
  end

  @doc "Create several blocks, returning their ids and the set of dirtied ids."
  @spec create_blocks([map()]) :: {[String.t()], MapSet.t()}
  def create_blocks(attrs_list) do
    Enum.map_reduce(attrs_list, MapSet.new(), fn attrs, dirty ->
      {:ok, block} = create_block(attrs)
      {block.id, MapSet.put(dirty, block.id)}
    end)
  end

  @doc """
  Apply `:value`, `:description`, and `:limit` changes to a block.

  Change keys may be atoms or strings. Returns `{:error, :exceeds_limit}` if the
  result would be longer than the block's limit.
  """
  @spec update_block(String.t(), map()) :: {:ok, block()} | {:error, term()}
  def update_block(block_id, changes) do
    with {:ok, block} <- get_block(block_id) do
      block
      |> maybe_put(changes, :value)
      |> maybe_put(changes, :description)
      |> maybe_put(changes, :limit)
      |> Map.put(:updated_at, now_iso())
      |> persist_block()
    end
  end

  @doc "Replace a block's value, rejecting anything past its limit."
  @spec save_block_value(block(), String.t()) :: {:ok, block()} | {:error, :exceeds_limit}
  def save_block_value(block, new_value) do
    if String.length(new_value) > block.limit do
      {:error, :exceeds_limit}
    else
      persist_block(%{block | value: new_value, updated_at: now_iso()})
    end
  end

  @doc """
  Delete a block and detach it from every agent holding it.

  Returns the names of the agents whose records changed, so the caller can mark
  them dirty — otherwise their `block_ids` would still list the deleted block
  on disk after the next restart.
  """
  @spec delete_block(String.t()) :: {[String.t()], :ok}
  def delete_block(block_id) do
    :ets.delete(@blocks_table, block_id)

    dirtied =
      @agents_table
      |> :ets.tab2list()
      |> Enum.flat_map(fn {name, agent} ->
        if block_id in (agent.block_ids || []) do
          :ets.insert(
            @agents_table,
            {name, %{agent | block_ids: List.delete(agent.block_ids, block_id)}}
          )

          [name]
        else
          []
        end
      end)

    {dirtied, :ok}
  end

  @doc "Resolve block ids to blocks, preserving order and skipping missing ids."
  @spec resolve_blocks([String.t()]) :: [block()]
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

  @doc "Find an agent's block by label."
  @spec find_agent_block(String.t(), String.t()) ::
          {:ok, block()} | {:error, :block_not_found | :agent_not_found}
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

  @doc "`:ok` if the block may be written, `{:error, :read_only}` otherwise."
  @spec writable?(block()) :: :ok | {:error, :read_only}
  def writable?(block), do: if(block.read_only, do: {:error, :read_only}, else: :ok)

  @doc "Render blocks into the tagged form injected into an agent's context."
  @spec compile_blocks([block()]) :: String.t()
  def compile_blocks(blocks), do: Enum.map_join(blocks, "\n\n", &compile_block/1)

  # Agents

  @doc "Whether the agent count has reached `MemoryStore.Config.max_agents/0`."
  @spec max_agents_reached?() :: boolean()
  def max_agents_reached?, do: :ets.info(@agents_table, :size) >= Config.max_agents()

  @doc "Whether an agent with this name exists."
  @spec agent_exists?(String.t()) :: boolean()
  def agent_exists?(name), do: :ets.lookup(@agents_table, name) != []

  @doc "Insert or replace an agent record."
  @spec insert_agent(agent()) :: {:ok, agent()}
  def insert_agent(agent) do
    :ets.insert(@agents_table, {agent.name, agent})
    {:ok, agent}
  end

  @doc "Look up an agent by name."
  @spec get_agent(String.t()) :: {:ok, agent()} | {:error, :not_found}
  def get_agent(name) do
    case :ets.lookup(@agents_table, name) do
      [{^name, agent}] -> {:ok, agent}
      [] -> {:error, :not_found}
    end
  end

  @doc "All agents, oldest first."
  @spec list_agents() :: [agent()]
  def list_agents do
    @agents_table
    |> :ets.tab2list()
    |> Enum.map(fn {_name, agent} -> agent end)
    |> Enum.sort_by(& &1.created_at)
  end

  # Recall

  @doc "An agent's recall entries, newest first."
  @spec get_recall(String.t()) :: [map()]
  def get_recall(agent_name) do
    case :ets.lookup(@recall_table, agent_name) do
      [{^agent_name, entries}] -> entries
      [] -> []
    end
  end

  @doc """
  Append a recall entry.

  Entries past `MemoryStore.Config.recall_limit/0` are dropped from ETS. They
  remain in the on-disk JSONL, which is append-ordered oldest first.
  """
  @spec add_recall(String.t(), atom(), String.t(), map()) :: {:ok, map()}
  def add_recall(agent_name, role, content, metadata) do
    entry = %{
      id: generate_id(),
      role: role,
      content: content,
      metadata: metadata,
      timestamp: now_iso()
    }

    updated = [entry | get_recall(agent_name)] |> Enum.take(Config.recall_limit())
    :ets.insert(@recall_table, {agent_name, updated})
    {:ok, entry}
  end

  @doc "Case-insensitive substring search over recall, with `:limit` and `:page`."
  @spec search_recall(String.t(), String.t(), keyword()) :: [map()]
  def search_recall(agent_name, query, opts) do
    limit = Keyword.get(opts, :limit, 10)
    page = Keyword.get(opts, :page, 0)
    query_down = String.downcase(query)

    agent_name
    |> get_recall()
    |> Enum.filter(&String.contains?(String.downcase(&1.content), query_down))
    |> Enum.drop(page * limit)
    |> Enum.take(limit)
  end

  @doc """
  Recall entries whose timestamp falls within an inclusive ISO-8601 range.

  Timestamps are compared as strings, which is correct because they are all
  written by `DateTime.to_iso8601/1` in UTC and so sort lexicographically.
  """
  @spec search_recall_by_date(String.t(), String.t(), String.t(), keyword()) :: [map()]
  def search_recall_by_date(agent_name, start_date, end_date, opts) do
    limit = Keyword.get(opts, :limit, 10)

    agent_name
    |> get_recall()
    |> Enum.filter(&(&1.timestamp >= start_date and &1.timestamp <= end_date))
    |> Enum.take(limit)
  end

  # Archival

  @doc "An agent's archival entries held in ETS, newest first."
  @spec get_archival(String.t()) :: [map()]
  def get_archival(agent_name) do
    case :ets.lookup(@archival_table, agent_name) do
      [{^agent_name, entries}] -> entries
      [] -> []
    end
  end

  @doc """
  Total archival entries for an agent.

  Counts lines in the JSONL file once ETS is at capacity, so the number does not
  silently plateau at the ETS limit.
  """
  @spec count_archival(String.t()) :: non_neg_integer()
  def count_archival(agent_name) do
    ets_entries = get_archival(agent_name)
    path = archival_path(agent_name)

    if length(ets_entries) >= Config.archival_ets_limit() and File.exists?(path) do
      path
      |> File.stream!()
      |> Stream.reject(&(String.trim(&1) == ""))
      |> Enum.count()
    else
      length(ets_entries)
    end
  end

  @doc "Insert an archival passage."
  @spec insert_archival(String.t(), String.t(), [String.t()]) :: {:ok, map()}
  def insert_archival(agent_name, content, tags) do
    passage = %{id: generate_id(), content: content, tags: tags, timestamp: now_iso()}

    updated = [passage | get_archival(agent_name)] |> Enum.take(Config.archival_ets_limit())
    :ets.insert(@archival_table, {agent_name, updated})
    {:ok, passage}
  end

  @doc """
  Case-insensitive substring search over archival passages.

  `:tags` narrows to passages carrying at least one of the given tags; `:limit`
  and `:page` paginate.
  """
  @spec search_archival(String.t(), String.t(), keyword()) :: [map()]
  def search_archival(agent_name, query, opts) do
    tags_filter = Keyword.get(opts, :tags, [])
    limit = Keyword.get(opts, :limit, 10)
    page = Keyword.get(opts, :page, 0)
    query_down = String.downcase(query)

    agent_name
    |> archival_for_search()
    |> filter_by_tags(tags_filter)
    |> Enum.filter(&String.contains?(String.downcase(&1.content), query_down))
    |> Enum.drop(page * limit)
    |> Enum.take(limit)
  end

  @doc "Remove one passage by id."
  @spec delete_archival(String.t(), String.t()) :: :ok
  def delete_archival(agent_name, passage_id) do
    updated = Enum.reject(get_archival(agent_name), &(&1.id == passage_id))
    :ets.insert(@archival_table, {agent_name, updated})
    :ok
  end

  @doc "A page of archival passages plus the total count."
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

  @doc "Path of an agent's archival JSONL file."
  @spec archival_path(String.t()) :: String.t()
  def archival_path(agent_name),
    do: Path.join([data_dir(), "agents", agent_name, "archival.jsonl"])

  # Private

  # Once ETS holds a full page, searching only ETS would miss older passages, so
  # fall back to the complete on-disk record.
  defp archival_for_search(agent_name) do
    ets_entries = get_archival(agent_name)
    path = archival_path(agent_name)

    if length(ets_entries) >= Config.archival_ets_limit() and File.exists?(path) do
      Persistence.load_jsonl(path)
    else
      ets_entries
    end
  end

  defp build_block(attrs) do
    # One clock read, so a freshly created block has created_at == updated_at
    # and "has this been edited?" is a simple comparison.
    now = now_iso()

    %{
      id: generate_id(),
      label: attr(attrs, :label),
      description: attr(attrs, :description, ""),
      value: attr(attrs, :value, ""),
      limit: attr(attrs, :limit, Config.default_block_limit()),
      read_only: attr(attrs, :read_only, false),
      created_at: now,
      updated_at: now
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

  defp persist_block(block) do
    if String.length(block.value) > block.limit do
      {:error, :exceeds_limit}
    else
      :ets.insert(@blocks_table, {block.id, block})
      {:ok, block}
    end
  end

  defp compile_block(block) do
    desc = if block.description in [nil, ""], do: "", else: "<!-- #{block.description} -->\n"

    """
    <memory_block label="#{block.label}" read_only="#{block.read_only}">
    #{desc}#{block.value}
    </memory_block>
    """
    |> String.trim_trailing("\n")
  end

  defp filter_by_tags(entries, []), do: entries

  defp filter_by_tags(entries, tags),
    do: Enum.filter(entries, fn entry -> Enum.any?(tags, &(&1 in (entry.tags || []))) end)

  defp generate_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  defp now_iso, do: DateTime.to_iso8601(DateTime.utc_now())
end
