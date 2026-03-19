defmodule Ichor.MemoryStore do
  @moduledoc """
  Letta-compatible agent memory system. Three tiers:

  ## Core Memory (in-context blocks -- analogous to RAM)
  Named blocks pinned to agent context. Each block has:
  - `label` -- unique name ("persona", "human", "organization", etc.)
  - `description` -- tells the agent what this block is for
  - `value` -- the content (text, up to `limit` chars)
  - `limit` -- character cap (default 2000)
  - `read_only` -- if true, agent tools cannot modify it

  Blocks can be shared between agents (same block ID, multiple agents).

  ## Recall Memory (conversation history -- searchable)
  Chronological message log per agent. Supports text search and date
  range queries. Auto-managed, most recent first.

  ## Archival Memory (long-term storage -- analogous to disk)
  Unlimited passage store with tags. Keyword search (no vector DB
  dependency). Agents insert/search/delete via MCP tools.

  ## Persistence
  Storage: `~/.ichor/memory/`
  - `blocks/` -- one JSON file per block (shared, not per-agent)
  - `agents/{name}/` -- agent config, recall JSONL, archival JSONL

  ETS for hot reads, periodic flush to disk.
  """
  use GenServer

  alias Ichor.MemoryStore.Archival
  alias Ichor.MemoryStore.Blocks
  alias Ichor.MemoryStore.Broadcast
  alias Ichor.MemoryStore.Persistence
  alias Ichor.MemoryStore.Recall
  alias Ichor.MemoryStore.Tables

  # ═══════════════════════════════════════════════════════
  # Client API -- Blocks
  # ═══════════════════════════════════════════════════════

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Create a standalone block. Returns {:ok, block}."
  def create_block(attrs) do
    GenServer.call(__MODULE__, {:create_block, attrs})
  end

  @doc "Get a block by ID."
  def get_block(block_id) do
    GenServer.call(__MODULE__, {:get_block, block_id})
  end

  @doc "Update a block's value, limit, or description."
  def update_block(block_id, changes) do
    GenServer.call(__MODULE__, {:update_block, block_id, changes})
  end

  @doc "Delete a block (detaches from all agents)."
  def delete_block(block_id) do
    GenServer.call(__MODULE__, {:delete_block, block_id})
  end

  @doc "List all blocks, optionally filtered by label."
  def list_blocks(opts \\ []) do
    GenServer.call(__MODULE__, {:list_blocks, opts})
  end

  # ═══════════════════════════════════════════════════════
  # Client API -- Agents
  # ═══════════════════════════════════════════════════════

  @doc """
  Create an agent with initial memory blocks.
  `memory_blocks` is a list of %{label, value, description?, limit?}.
  `block_ids` is a list of existing block IDs to attach.
  """
  def create_agent(name, memory_blocks \\ [], block_ids \\ []) do
    GenServer.call(__MODULE__, {:create_agent, name, memory_blocks, block_ids})
  end

  @doc "Get agent config + all attached block IDs."
  def get_agent(name) do
    GenServer.call(__MODULE__, {:get_agent, name})
  end

  @doc "Attach an existing block to an agent."
  def attach_block(agent_name, block_id) do
    GenServer.call(__MODULE__, {:attach_block, agent_name, block_id})
  end

  @doc "Detach a block from an agent (does not delete the block)."
  def detach_block(agent_name, block_id) do
    GenServer.call(__MODULE__, {:detach_block, agent_name, block_id})
  end

  @doc "List all registered agents."
  def list_agents do
    GenServer.call(__MODULE__, :list_agents)
  end

  @doc """
  Read all core memory for an agent: renders blocks into context format.
  This is what gets injected into the agent's system prompt.
  """
  def read_core_memory(agent_name) do
    GenServer.call(__MODULE__, {:read_core_memory, agent_name})
  end

  @doc """
  Compile core memory into a system prompt segment.
  Returns a formatted string like Letta's Memory.compile().
  """
  def compile_memory(agent_name) do
    GenServer.call(__MODULE__, {:compile_memory, agent_name})
  end

  # ═══════════════════════════════════════════════════════
  # Client API -- Memory Tools (agent-facing, Letta V2)
  # ═══════════════════════════════════════════════════════

  @doc "Replace text in a block. Letta's memory_replace."
  def memory_replace(agent_name, block_label, old_text, new_text) do
    GenServer.call(__MODULE__, {:memory_replace, agent_name, block_label, old_text, new_text})
  end

  @doc "Insert text at a position in a block. Letta's memory_insert."
  def memory_insert(agent_name, block_label, position, text) do
    GenServer.call(__MODULE__, {:memory_insert, agent_name, block_label, position, text})
  end

  @doc "Rewrite a block entirely. Letta's memory_rethink."
  def memory_rethink(agent_name, block_label, new_value) do
    GenServer.call(__MODULE__, {:memory_rethink, agent_name, block_label, new_value})
  end

  # ═══════════════════════════════════════════════════════
  # Client API -- Recall Memory
  # ═══════════════════════════════════════════════════════

  @doc "Add a message to recall memory."
  def add_recall(agent_name, role, content, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:add_recall, agent_name, role, content, metadata})
  end

  @doc "Search recall memory by text. Letta's conversation_search."
  def conversation_search(agent_name, query, opts \\ []) do
    GenServer.call(__MODULE__, {:conversation_search, agent_name, query, opts})
  end

  @doc "Search recall memory by date range. Letta's conversation_search_date."
  def conversation_search_date(agent_name, start_date, end_date, opts \\ []) do
    GenServer.call(
      __MODULE__,
      {:conversation_search_date, agent_name, start_date, end_date, opts}
    )
  end

  # ═══════════════════════════════════════════════════════
  # Client API -- Archival Memory
  # ═══════════════════════════════════════════════════════

  @doc "Insert a passage into archival memory. Letta's archival_memory_insert."
  def archival_memory_insert(agent_name, content, tags \\ []) do
    GenServer.call(__MODULE__, {:archival_insert, agent_name, content, tags})
  end

  @doc "Search archival memory by keyword. Letta's archival_memory_search."
  def archival_memory_search(agent_name, query, opts \\ []) do
    GenServer.call(__MODULE__, {:archival_search, agent_name, query, opts})
  end

  @doc "Delete an archival passage by ID."
  def archival_memory_delete(agent_name, passage_id) do
    GenServer.call(__MODULE__, {:archival_delete, agent_name, passage_id})
  end

  @doc "List archival passages (paginated)."
  def archival_memory_list(agent_name, opts \\ []) do
    GenServer.call(__MODULE__, {:archival_list, agent_name, opts})
  end

  @doc "Data directory path."
  def data_dir, do: Tables.data_dir()

  # ═══════════════════════════════════════════════════════
  # Server -- Init
  # ═══════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    :ets.new(Tables.blocks_table(), [:named_table, :public, :set])
    :ets.new(Tables.agents_table(), [:named_table, :public, :set])
    :ets.new(Tables.recall_table(), [:named_table, :public, :set])
    :ets.new(Tables.archival_table(), [:named_table, :public, :set])
    Persistence.load_from_disk()
    schedule_flush()
    {:ok, %{dirty_blocks: MapSet.new(), dirty_agents: MapSet.new()}}
  end

  # ═══════════════════════════════════════════════════════
  # Server -- Block Handlers
  # ═══════════════════════════════════════════════════════

  @impl true
  def handle_call({:create_block, attrs}, _from, state) do
    if Blocks.max_blocks_reached?() do
      {:reply, {:error, :max_blocks_reached}, state}
    else
      {:ok, block} = Blocks.create(attrs)
      {:reply, {:ok, block}, %{state | dirty_blocks: MapSet.put(state.dirty_blocks, block.id)}}
    end
  end

  def handle_call({:get_block, block_id}, _from, state) do
    {:reply, Blocks.get(block_id), state}
  end

  def handle_call({:update_block, block_id, changes}, _from, state) do
    case Blocks.update(block_id, changes) do
      {:ok, updated} ->
        {:reply, {:ok, updated},
         %{state | dirty_blocks: MapSet.put(state.dirty_blocks, block_id)}}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:delete_block, block_id}, _from, state) do
    :ok = Blocks.delete(block_id)
    {:reply, :ok, %{state | dirty_blocks: MapSet.put(state.dirty_blocks, block_id)}}
  end

  def handle_call({:list_blocks, opts}, _from, state) do
    {:reply, {:ok, Blocks.list(opts)}, state}
  end

  # ═══════════════════════════════════════════════════════
  # Server -- Agent Handlers
  # ═══════════════════════════════════════════════════════

  def handle_call({:create_agent, name, memory_blocks, extra_block_ids}, _from, state) do
    cond do
      :ets.info(Tables.agents_table(), :size) >= Tables.max_agents() ->
        {:reply, {:error, :max_agents_reached}, state}

      :ets.lookup(Tables.agents_table(), name) != [] ->
        {:reply, {:error, :already_exists}, state}

      true ->
        {created_ids, dirty} = Blocks.create_many(memory_blocks)
        dirty = MapSet.union(state.dirty_blocks, dirty)

        all_block_ids = Enum.reverse(created_ids) ++ extra_block_ids

        agent = %{
          name: name,
          block_ids: all_block_ids,
          created_at: DateTime.to_iso8601(DateTime.utc_now()),
          updated_at: DateTime.to_iso8601(DateTime.utc_now())
        }

        :ets.insert(Tables.agents_table(), {name, agent})
        Broadcast.agent_changed(name, :created)

        {:reply, {:ok, agent},
         %{state | dirty_blocks: dirty, dirty_agents: MapSet.put(state.dirty_agents, name)}}
    end
  end

  def handle_call({:get_agent, name}, _from, state) do
    case :ets.lookup(Tables.agents_table(), name) do
      [{^name, agent}] -> {:reply, {:ok, agent}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:attach_block, agent_name, block_id}, _from, state) do
    with [{^agent_name, agent}] <- :ets.lookup(Tables.agents_table(), agent_name),
         {:ok, _block} <- Blocks.get(block_id) do
      if block_id in agent.block_ids do
        {:reply, {:ok, agent}, state}
      else
        updated = %{
          agent
          | block_ids: agent.block_ids ++ [block_id],
            updated_at: DateTime.to_iso8601(DateTime.utc_now())
        }

        :ets.insert(Tables.agents_table(), {agent_name, updated})

        {:reply, {:ok, updated},
         %{state | dirty_agents: MapSet.put(state.dirty_agents, agent_name)}}
      end
    else
      _ -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:detach_block, agent_name, block_id}, _from, state) do
    case :ets.lookup(Tables.agents_table(), agent_name) do
      [{^agent_name, agent}] ->
        updated = %{
          agent
          | block_ids: List.delete(agent.block_ids, block_id),
            updated_at: DateTime.to_iso8601(DateTime.utc_now())
        }

        :ets.insert(Tables.agents_table(), {agent_name, updated})

        {:reply, {:ok, updated},
         %{state | dirty_agents: MapSet.put(state.dirty_agents, agent_name)}}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:list_agents, _from, state) do
    agents =
      :ets.tab2list(Tables.agents_table())
      |> Enum.map(fn {_name, agent} ->
        blocks = Blocks.resolve(agent.block_ids)
        block_labels = Enum.map(blocks, & &1.label)
        recall_count = length(Recall.get(agent.name))
        archival_count = Archival.count(agent.name)

        Map.merge(agent, %{
          block_labels: block_labels,
          recall_count: recall_count,
          archival_count: archival_count
        })
      end)
      |> Enum.sort_by(& &1.created_at)

    {:reply, {:ok, agents}, state}
  end

  def handle_call({:read_core_memory, agent_name}, _from, state) do
    case :ets.lookup(Tables.agents_table(), agent_name) do
      [{^agent_name, agent}] ->
        blocks = Blocks.resolve(agent.block_ids)

        result = %{
          agent: agent_name,
          blocks:
            Enum.map(blocks, fn b ->
              %{
                label: b.label,
                description: b.description,
                value: b.value,
                read_only: b.read_only
              }
            end),
          recall_count: length(Recall.get(agent_name)),
          archival_count: Archival.count(agent_name)
        }

        {:reply, {:ok, result}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:compile_memory, agent_name}, _from, state) do
    case :ets.lookup(Tables.agents_table(), agent_name) do
      [{^agent_name, agent}] ->
        {:reply, {:ok, agent.block_ids |> Blocks.resolve() |> Blocks.compile()}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  # ═══════════════════════════════════════════════════════
  # Server -- Memory Tool Handlers (V2 line-aware)
  # ═══════════════════════════════════════════════════════

  def handle_call({:memory_replace, agent_name, block_label, old_text, new_text}, _from, state) do
    with {:ok, block} <- Blocks.find_agent_block(agent_name, block_label),
         :ok <- Blocks.writable?(block) do
      do_replace(block, old_text, new_text, state)
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:memory_insert, agent_name, block_label, position, text}, _from, state) do
    with {:ok, block} <- Blocks.find_agent_block(agent_name, block_label),
         :ok <- Blocks.writable?(block) do
      lines = String.split(block.value, "\n")
      pos = min(max(position, 0), length(lines))
      {before, after_lines} = Enum.split(lines, pos)

      case Blocks.save_value(block, Enum.join(before ++ [text] ++ after_lines, "\n")) do
        {:ok, updated} ->
          {:reply, {:ok, updated},
           %{state | dirty_blocks: MapSet.put(state.dirty_blocks, block.id)}}

        error ->
          {:reply, error, state}
      end
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:memory_rethink, agent_name, block_label, new_value}, _from, state) do
    with {:ok, block} <- Blocks.find_agent_block(agent_name, block_label),
         :ok <- Blocks.writable?(block) do
      case Blocks.save_value(block, new_value) do
        {:ok, updated} ->
          {:reply, {:ok, updated},
           %{state | dirty_blocks: MapSet.put(state.dirty_blocks, block.id)}}

        error ->
          {:reply, error, state}
      end
    else
      error -> {:reply, error, state}
    end
  end

  # ═══════════════════════════════════════════════════════
  # Server -- Recall Memory Handlers
  # ═══════════════════════════════════════════════════════

  def handle_call({:add_recall, agent_name, role, content, metadata}, _from, state) do
    {:ok, entry} = Recall.add(agent_name, role, content, metadata)
    {:reply, {:ok, entry}, %{state | dirty_agents: MapSet.put(state.dirty_agents, agent_name)}}
  end

  def handle_call({:conversation_search, agent_name, query, opts}, _from, state) do
    {:reply, {:ok, Recall.search(agent_name, query, opts)}, state}
  end

  def handle_call(
        {:conversation_search_date, agent_name, start_date, end_date, opts},
        _from,
        state
      ) do
    {:reply, {:ok, Recall.search_by_date(agent_name, start_date, end_date, opts)}, state}
  end

  # ═══════════════════════════════════════════════════════
  # Server -- Archival Memory Handlers
  # ═══════════════════════════════════════════════════════

  def handle_call({:archival_insert, agent_name, content, tags}, _from, state) do
    {:ok, passage} = Archival.insert(agent_name, content, tags)
    {:reply, {:ok, passage}, %{state | dirty_agents: MapSet.put(state.dirty_agents, agent_name)}}
  end

  def handle_call({:archival_search, agent_name, query, opts}, _from, state) do
    {:reply, {:ok, Archival.search(agent_name, query, opts)}, state}
  end

  def handle_call({:archival_delete, agent_name, passage_id}, _from, state) do
    :ok = Archival.delete(agent_name, passage_id)
    {:reply, :ok, %{state | dirty_agents: MapSet.put(state.dirty_agents, agent_name)}}
  end

  def handle_call({:archival_list, agent_name, opts}, _from, state) do
    {:reply, {:ok, Archival.list(agent_name, opts)}, state}
  end

  # ═══════════════════════════════════════════════════════
  # Server -- Flush
  # ═══════════════════════════════════════════════════════

  @impl true
  def handle_info(:flush_to_disk, state) do
    Persistence.flush_dirty(state)
    schedule_flush()
    {:noreply, %{state | dirty_blocks: MapSet.new(), dirty_agents: MapSet.new()}}
  end

  # ═══════════════════════════════════════════════════════
  # Utilities
  # ═══════════════════════════════════════════════════════

  defp schedule_flush, do: Process.send_after(self(), :flush_to_disk, 10_000)

  defp do_replace(block, old_text, new_text, state) do
    if String.contains?(block.value, old_text) do
      new_value = String.replace(block.value, old_text, new_text, global: false)

      case Blocks.save_value(block, new_value) do
        {:ok, updated} ->
          {:reply, {:ok, updated},
           %{state | dirty_blocks: MapSet.put(state.dirty_blocks, block.id)}}

        error ->
          {:reply, error, state}
      end
    else
      {:reply, {:error, :text_not_found}, state}
    end
  end
end
