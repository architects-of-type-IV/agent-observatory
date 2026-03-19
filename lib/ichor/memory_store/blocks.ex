defmodule Ichor.MemoryStore.Blocks do
  @moduledoc """
  Block shaping and block-related ETS operations for the memory store.
  """

  alias Ichor.MemoryStore.Broadcast
  alias Ichor.MemoryStore.Tables

  @doc "True if the block store has reached the maximum allowed blocks."
  @spec max_blocks_reached?() :: boolean()
  def max_blocks_reached? do
    :ets.info(Tables.blocks_table(), :size) >= Tables.max_blocks()
  end

  @doc "Look up a block by id."
  @spec get(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get(block_id) do
    case :ets.lookup(Tables.blocks_table(), block_id) do
      [{^block_id, block}] -> {:ok, block}
      [] -> {:error, :not_found}
    end
  end

  @doc "Return all blocks, optionally filtered by label."
  @spec list(keyword()) :: [map()]
  def list(opts \\ []) do
    label_filter = Keyword.get(opts, :label)

    Tables.blocks_table()
    |> :ets.tab2list()
    |> Enum.map(fn {_id, block} -> block end)
    |> then(fn blocks ->
      if label_filter, do: Enum.filter(blocks, &(&1.label == label_filter)), else: blocks
    end)
    |> Enum.sort_by(& &1.created_at)
  end

  @doc "Create a new block from attrs and insert it into ETS."
  @spec create(map()) :: {:ok, map()}
  def create(attrs) do
    block = build(attrs)
    :ets.insert(Tables.blocks_table(), {block.id, block})
    {:ok, block}
  end

  @doc "Create multiple blocks and return their ids along with the dirty set."
  @spec create_many([map()]) :: {[String.t()], MapSet.t()}
  def create_many(attrs_list) do
    Enum.map_reduce(attrs_list, MapSet.new(), fn attrs, dirty ->
      {:ok, block} = create(attrs)
      {block.id, MapSet.put(dirty, block.id)}
    end)
  end

  @doc "Apply field changes to a block and persist to ETS."
  @spec update(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update(block_id, changes) do
    with {:ok, block} <- get(block_id) do
      updated =
        block
        |> maybe_put(changes, :value)
        |> maybe_put(changes, :description)
        |> maybe_put(changes, :limit)
        |> Map.put(:updated_at, now_iso())

      persist_updated(updated)
    end
  end

  @doc "Save a new value to a block, returning an error if it exceeds the limit."
  @spec save_value(map(), String.t()) :: {:ok, map()} | {:error, :exceeds_limit}
  def save_value(block, new_value) do
    if String.length(new_value) > block.limit do
      {:error, :exceeds_limit}
    else
      updated = %{block | value: new_value, updated_at: now_iso()}
      persist_updated(updated)
    end
  end

  @doc "Delete a block from ETS and remove it from all agent block_ids lists."
  @spec delete(String.t()) :: :ok
  def delete(block_id) do
    :ets.delete(Tables.blocks_table(), block_id)

    :ets.tab2list(Tables.agents_table())
    |> Enum.each(fn {name, agent} ->
      if block_id in (agent.block_ids || []) do
        updated = %{agent | block_ids: List.delete(agent.block_ids, block_id)}
        :ets.insert(Tables.agents_table(), {name, updated})
      end
    end)

    :ok
  end

  @doc "Resolve a list of block ids to their block maps, skipping missing ones."
  @spec resolve([String.t()]) :: [map()]
  def resolve(block_ids) do
    Enum.reduce(block_ids, [], fn id, acc ->
      case :ets.lookup(Tables.blocks_table(), id) do
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
    case :ets.lookup(Tables.agents_table(), agent_name) do
      [{^agent_name, agent}] ->
        case Enum.find(resolve(agent.block_ids), &(&1.label == block_label)) do
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
  @spec compile([map()]) :: String.t()
  def compile(blocks), do: Enum.map_join(blocks, "\n\n", &compile_block/1)

  @doc "Build a new block map from attrs, generating an id and timestamps."
  @spec build(map()) :: map()
  def build(attrs) do
    %{
      id: generate_id(),
      label: attr(attrs, :label),
      description: attr(attrs, :description, ""),
      value: attr(attrs, :value, ""),
      limit: attr(attrs, :limit, Tables.default_block_limit()),
      read_only: attr(attrs, :read_only, false),
      created_at: now_iso(),
      updated_at: now_iso()
    }
  end

  @doc "Get an attr from a map by atom or string key, returning default if absent."
  @spec attr(map(), atom(), term()) :: term()
  def attr(map, key, default \\ nil), do: map[key] || map[to_string(key)] || default

  @doc "Put a key from changes map into map if present as atom or string key."
  @spec maybe_put(map(), map(), atom()) :: map()
  def maybe_put(map, changes, key) do
    str_key = to_string(key)

    cond do
      Map.has_key?(changes, key) -> Map.put(map, key, Map.get(changes, key))
      Map.has_key?(changes, str_key) -> Map.put(map, key, Map.get(changes, str_key))
      true -> map
    end
  end

  defp persist_updated(updated) do
    if String.length(updated.value) > updated.limit do
      {:error, :exceeds_limit}
    else
      :ets.insert(Tables.blocks_table(), {updated.id, updated})
      Broadcast.block_changed(updated.id, updated.label)
      {:ok, updated}
    end
  end

  defp compile_block(block) do
    header = "<memory_block label=\"#{block.label}\" read_only=\"#{block.read_only}\">"
    footer = "</memory_block>"
    desc = if block.description != "", do: "<!-- #{block.description} -->\n", else: ""
    "#{header}\n#{desc}#{block.value}\n#{footer}"
  end

  defp generate_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  defp now_iso, do: DateTime.to_iso8601(DateTime.utc_now())
end
