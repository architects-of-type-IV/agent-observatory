defmodule Ichor.MemoryStore.Blocks do
  @moduledoc """
  Block shaping and block-related ETS operations for the memory store.
  """

  alias Ichor.MemoryStore.Broadcast
  alias Ichor.MemoryStore.Tables

  def max_blocks_reached? do
    :ets.info(Tables.blocks_table(), :size) >= Tables.max_blocks()
  end

  def get(block_id) do
    case :ets.lookup(Tables.blocks_table(), block_id) do
      [{^block_id, block}] -> {:ok, block}
      [] -> {:error, :not_found}
    end
  end

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

  def create(attrs) do
    block = build(attrs)
    :ets.insert(Tables.blocks_table(), {block.id, block})
    {:ok, block}
  end

  def create_many(attrs_list) do
    Enum.map_reduce(attrs_list, MapSet.new(), fn attrs, dirty ->
      {:ok, block} = create(attrs)
      {block.id, MapSet.put(dirty, block.id)}
    end)
  end

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

  def save_value(block, new_value) do
    if String.length(new_value) > block.limit do
      {:error, :exceeds_limit}
    else
      updated = %{block | value: new_value, updated_at: now_iso()}
      persist_updated(updated)
    end
  end

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

  def resolve(block_ids) do
    Enum.reduce(block_ids, [], fn id, acc ->
      case :ets.lookup(Tables.blocks_table(), id) do
        [{^id, block}] -> [block | acc]
        [] -> acc
      end
    end)
    |> Enum.reverse()
  end

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

  def writable?(block) do
    if block.read_only, do: {:error, :read_only}, else: :ok
  end

  def compile(blocks), do: Enum.map_join(blocks, "\n\n", &compile_block/1)

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

  def attr(map, key, default \\ nil), do: map[key] || map[to_string(key)] || default

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
