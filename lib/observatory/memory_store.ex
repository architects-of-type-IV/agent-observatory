defmodule Observatory.MemoryStore do
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
  Storage: `~/.observatory/memory/`
  - `blocks/` -- one JSON file per block (shared, not per-agent)
  - `agents/{name}/` -- agent config, recall JSONL, archival JSONL

  ETS for hot reads, periodic flush to disk.
  """
  use GenServer
  require Logger

  @blocks_table :letta_blocks
  @agents_table :letta_agents
  @recall_table :letta_recall
  @archival_table :letta_archival
  @default_block_limit 2000
  @recall_limit 200
  # Cap archival entries kept in ETS per agent. Older entries stay on disk only.
  # Prevents ETS memory bloat -- agents with large archives search disk on miss.
  @archival_ets_limit 500
  # Max agents. Beyond this, create_agent is rejected.
  @max_agents 100
  # Max blocks total (shared + per-agent).
  @max_blocks 1000

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
    GenServer.call(__MODULE__, {:conversation_search_date, agent_name, start_date, end_date, opts})
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
  def data_dir, do: Path.expand("~/.observatory/memory")

  # ═══════════════════════════════════════════════════════
  # Server -- Init
  # ═══════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    :ets.new(@blocks_table, [:named_table, :public, :set])
    :ets.new(@agents_table, [:named_table, :public, :set])
    :ets.new(@recall_table, [:named_table, :public, :set])
    :ets.new(@archival_table, [:named_table, :public, :set])
    load_from_disk()
    schedule_flush()
    {:ok, %{dirty_blocks: MapSet.new(), dirty_agents: MapSet.new()}}
  end

  # ═══════════════════════════════════════════════════════
  # Server -- Block Handlers
  # ═══════════════════════════════════════════════════════

  @impl true
  def handle_call({:create_block, attrs}, _from, state) do
    if :ets.info(@blocks_table, :size) >= @max_blocks do
      {:reply, {:error, :max_blocks_reached}, state}
    else
      block = %{
        id: generate_id(),
        label: attrs[:label] || attrs["label"],
        description: attrs[:description] || attrs["description"] || "",
        value: attrs[:value] || attrs["value"] || "",
        limit: attrs[:limit] || attrs["limit"] || @default_block_limit,
        read_only: attrs[:read_only] || attrs["read_only"] || false,
        created_at: now_iso(),
        updated_at: now_iso()
      }

      :ets.insert(@blocks_table, {block.id, block})

      {:reply, {:ok, block},
       %{state | dirty_blocks: MapSet.put(state.dirty_blocks, block.id)}}
    end
  end

  def handle_call({:get_block, block_id}, _from, state) do
    result =
      case :ets.lookup(@blocks_table, block_id) do
        [{^block_id, block}] -> {:ok, block}
        [] -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  def handle_call({:update_block, block_id, changes}, _from, state) do
    case :ets.lookup(@blocks_table, block_id) do
      [{^block_id, block}] ->
        updated =
          block
          |> maybe_put(changes, :value)
          |> maybe_put(changes, :description)
          |> maybe_put(changes, :limit)
          |> Map.put(:updated_at, now_iso())

        # Enforce character limit
        if String.length(updated.value) > updated.limit do
          {:reply, {:error, :exceeds_limit}, state}
        else
          :ets.insert(@blocks_table, {block_id, updated})
          broadcast_block_change(block_id, updated.label)
          {:reply, {:ok, updated},
           %{state | dirty_blocks: MapSet.put(state.dirty_blocks, block_id)}}
        end

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:delete_block, block_id}, _from, state) do
    :ets.delete(@blocks_table, block_id)

    # Detach from all agents
    :ets.tab2list(@agents_table)
    |> Enum.each(fn {name, agent} ->
      if block_id in (agent.block_ids || []) do
        updated = %{agent | block_ids: List.delete(agent.block_ids, block_id)}
        :ets.insert(@agents_table, {name, updated})
      end
    end)

    {:reply, :ok, %{state | dirty_blocks: MapSet.put(state.dirty_blocks, block_id)}}
  end

  def handle_call({:list_blocks, opts}, _from, state) do
    label_filter = Keyword.get(opts, :label)

    blocks =
      :ets.tab2list(@blocks_table)
      |> Enum.map(fn {_id, block} -> block end)
      |> then(fn blocks ->
        if label_filter, do: Enum.filter(blocks, &(&1.label == label_filter)), else: blocks
      end)
      |> Enum.sort_by(& &1.created_at)

    {:reply, {:ok, blocks}, state}
  end

  # ═══════════════════════════════════════════════════════
  # Server -- Agent Handlers
  # ═══════════════════════════════════════════════════════

  def handle_call({:create_agent, name, memory_blocks, extra_block_ids}, _from, state) do
    cond do
      :ets.info(@agents_table, :size) >= @max_agents ->
        {:reply, {:error, :max_agents_reached}, state}

      :ets.lookup(@agents_table, name) != [] ->
        {:reply, {:error, :already_exists}, state}

      true ->
        # Create blocks from inline definitions
        {created_ids, dirty} =
          Enum.reduce(memory_blocks, {[], state.dirty_blocks}, fn mb, {ids, d} ->
            block = %{
              id: generate_id(),
              label: mb[:label] || mb["label"],
              description: mb[:description] || mb["description"] || "",
              value: mb[:value] || mb["value"] || "",
              limit: mb[:limit] || mb["limit"] || @default_block_limit,
              read_only: mb[:read_only] || mb["read_only"] || false,
              created_at: now_iso(),
              updated_at: now_iso()
            }

            :ets.insert(@blocks_table, {block.id, block})
            {[block.id | ids], MapSet.put(d, block.id)}
          end)

        all_block_ids = Enum.reverse(created_ids) ++ extra_block_ids

        agent = %{
          name: name,
          block_ids: all_block_ids,
          created_at: now_iso(),
          updated_at: now_iso()
        }

        :ets.insert(@agents_table, {name, agent})
        broadcast_agent_change(name, :created)

        {:reply, {:ok, agent},
         %{state | dirty_blocks: dirty, dirty_agents: MapSet.put(state.dirty_agents, name)}}
    end
  end

  def handle_call({:get_agent, name}, _from, state) do
    case :ets.lookup(@agents_table, name) do
      [{^name, agent}] -> {:reply, {:ok, agent}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:attach_block, agent_name, block_id}, _from, state) do
    with [{^agent_name, agent}] <- :ets.lookup(@agents_table, agent_name),
         [{^block_id, _block}] <- :ets.lookup(@blocks_table, block_id) do
      if block_id in agent.block_ids do
        {:reply, {:ok, agent}, state}
      else
        updated = %{agent | block_ids: agent.block_ids ++ [block_id], updated_at: now_iso()}
        :ets.insert(@agents_table, {agent_name, updated})

        {:reply, {:ok, updated},
         %{state | dirty_agents: MapSet.put(state.dirty_agents, agent_name)}}
      end
    else
      _ -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:detach_block, agent_name, block_id}, _from, state) do
    case :ets.lookup(@agents_table, agent_name) do
      [{^agent_name, agent}] ->
        updated = %{agent | block_ids: List.delete(agent.block_ids, block_id), updated_at: now_iso()}
        :ets.insert(@agents_table, {agent_name, updated})

        {:reply, {:ok, updated},
         %{state | dirty_agents: MapSet.put(state.dirty_agents, agent_name)}}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:list_agents, _from, state) do
    agents =
      :ets.tab2list(@agents_table)
      |> Enum.map(fn {_name, agent} ->
        blocks = resolve_blocks(agent.block_ids)
        block_labels = Enum.map(blocks, & &1.label)
        recall_count = length(get_recall(agent.name))
        archival_count = archival_count_with_disk(agent.name)

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
    case :ets.lookup(@agents_table, agent_name) do
      [{^agent_name, agent}] ->
        blocks = resolve_blocks(agent.block_ids)

        result = %{
          agent: agent_name,
          blocks: Enum.map(blocks, fn b ->
            %{label: b.label, description: b.description, value: b.value, read_only: b.read_only}
          end),
          recall_count: length(get_recall(agent_name)),
          archival_count: archival_count_with_disk(agent_name)
        }

        {:reply, {:ok, result}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:compile_memory, agent_name}, _from, state) do
    case :ets.lookup(@agents_table, agent_name) do
      [{^agent_name, agent}] ->
        blocks = resolve_blocks(agent.block_ids)

        compiled =
          blocks
          |> Enum.map(fn b ->
            header = "<memory_block label=\"#{b.label}\" read_only=\"#{b.read_only}\">"
            footer = "</memory_block>"
            desc = if b.description != "", do: "<!-- #{b.description} -->\n", else: ""
            "#{header}\n#{desc}#{b.value}\n#{footer}"
          end)
          |> Enum.join("\n\n")

        {:reply, {:ok, compiled}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  # ═══════════════════════════════════════════════════════
  # Server -- Memory Tool Handlers (V2 line-aware)
  # ═══════════════════════════════════════════════════════

  def handle_call({:memory_replace, agent_name, block_label, old_text, new_text}, _from, state) do
    with {:ok, block} <- find_agent_block(agent_name, block_label),
         :ok <- check_writable(block) do
      if String.contains?(block.value, old_text) do
        new_value = String.replace(block.value, old_text, new_text, global: false)

        if String.length(new_value) > block.limit do
          {:reply, {:error, :exceeds_limit}, state}
        else
          updated = %{block | value: new_value, updated_at: now_iso()}
          :ets.insert(@blocks_table, {block.id, updated})
          broadcast_block_change(block.id, block.label)

          {:reply, {:ok, updated},
           %{state | dirty_blocks: MapSet.put(state.dirty_blocks, block.id)}}
        end
      else
        {:reply, {:error, :text_not_found}, state}
      end
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:memory_insert, agent_name, block_label, position, text}, _from, state) do
    with {:ok, block} <- find_agent_block(agent_name, block_label),
         :ok <- check_writable(block) do
      lines = String.split(block.value, "\n")
      pos = min(max(position, 0), length(lines))
      {before, after_lines} = Enum.split(lines, pos)
      new_value = Enum.join(before ++ [text] ++ after_lines, "\n")

      if String.length(new_value) > block.limit do
        {:reply, {:error, :exceeds_limit}, state}
      else
        updated = %{block | value: new_value, updated_at: now_iso()}
        :ets.insert(@blocks_table, {block.id, updated})
        broadcast_block_change(block.id, block.label)

        {:reply, {:ok, updated},
         %{state | dirty_blocks: MapSet.put(state.dirty_blocks, block.id)}}
      end
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:memory_rethink, agent_name, block_label, new_value}, _from, state) do
    with {:ok, block} <- find_agent_block(agent_name, block_label),
         :ok <- check_writable(block) do
      if String.length(new_value) > block.limit do
        {:reply, {:error, :exceeds_limit}, state}
      else
        updated = %{block | value: new_value, updated_at: now_iso()}
        :ets.insert(@blocks_table, {block.id, updated})
        broadcast_block_change(block.id, block.label)

        {:reply, {:ok, updated},
         %{state | dirty_blocks: MapSet.put(state.dirty_blocks, block.id)}}
      end
    else
      error -> {:reply, error, state}
    end
  end

  # ═══════════════════════════════════════════════════════
  # Server -- Recall Memory Handlers
  # ═══════════════════════════════════════════════════════

  def handle_call({:add_recall, agent_name, role, content, metadata}, _from, state) do
    recall = get_recall(agent_name)

    entry = %{
      id: generate_id(),
      role: role,
      content: content,
      metadata: metadata,
      timestamp: now_iso()
    }

    updated = [entry | recall] |> Enum.take(@recall_limit)
    :ets.insert(@recall_table, {agent_name, updated})

    {:reply, {:ok, entry},
     %{state | dirty_agents: MapSet.put(state.dirty_agents, agent_name)}}
  end

  def handle_call({:conversation_search, agent_name, query, opts}, _from, state) do
    recall = get_recall(agent_name)
    limit = Keyword.get(opts, :limit, 10)
    page = Keyword.get(opts, :page, 0)
    query_down = String.downcase(query)

    results =
      recall
      |> Enum.filter(fn e -> String.contains?(String.downcase(e.content), query_down) end)
      |> Enum.drop(page * limit)
      |> Enum.take(limit)

    {:reply, {:ok, results}, state}
  end

  def handle_call({:conversation_search_date, agent_name, start_date, end_date, opts}, _from, state) do
    recall = get_recall(agent_name)
    limit = Keyword.get(opts, :limit, 10)

    results =
      recall
      |> Enum.filter(fn e ->
        ts = e.timestamp
        ts >= start_date && ts <= end_date
      end)
      |> Enum.take(limit)

    {:reply, {:ok, results}, state}
  end

  # ═══════════════════════════════════════════════════════
  # Server -- Archival Memory Handlers
  # ═══════════════════════════════════════════════════════

  def handle_call({:archival_insert, agent_name, content, tags}, _from, state) do
    archival = get_archival(agent_name)

    passage = %{
      id: generate_id(),
      content: content,
      tags: tags,
      timestamp: now_iso()
    }

    # Keep only recent entries in ETS; older ones stay on disk only
    updated = [passage | archival] |> Enum.take(@archival_ets_limit)
    :ets.insert(@archival_table, {agent_name, updated})
    broadcast_agent_change(agent_name, :archival_insert)

    {:reply, {:ok, passage},
     %{state | dirty_agents: MapSet.put(state.dirty_agents, agent_name)}}
  end

  def handle_call({:archival_search, agent_name, query, opts}, _from, state) do
    # ETS holds at most @archival_ets_limit entries. If the agent has
    # more on disk, search disk directly to avoid missing older passages.
    archival = get_archival_for_search(agent_name)
    tags_filter = Keyword.get(opts, :tags, [])
    limit = Keyword.get(opts, :limit, 10)
    page = Keyword.get(opts, :page, 0)
    query_down = String.downcase(query)

    results =
      archival
      |> then(fn entries ->
        if tags_filter != [] do
          Enum.filter(entries, fn e ->
            Enum.any?(tags_filter, &(&1 in (e.tags || [])))
          end)
        else
          entries
        end
      end)
      |> Enum.filter(fn e ->
        String.contains?(String.downcase(e.content), query_down)
      end)
      |> Enum.drop(page * limit)
      |> Enum.take(limit)

    {:reply, {:ok, results}, state}
  end

  def handle_call({:archival_delete, agent_name, passage_id}, _from, state) do
    archival = get_archival(agent_name)
    updated = Enum.reject(archival, fn e -> e.id == passage_id end)
    :ets.insert(@archival_table, {agent_name, updated})

    {:reply, :ok,
     %{state | dirty_agents: MapSet.put(state.dirty_agents, agent_name)}}
  end

  def handle_call({:archival_list, agent_name, opts}, _from, state) do
    # Use full disk archive for listing to get accurate totals
    archival = get_archival_for_search(agent_name)
    limit = Keyword.get(opts, :limit, 50)
    page = Keyword.get(opts, :page, 0)

    results =
      archival
      |> Enum.drop(page * limit)
      |> Enum.take(limit)

    {:reply, {:ok, %{passages: results, total: length(archival)}}, state}
  end

  # ═══════════════════════════════════════════════════════
  # Server -- Flush
  # ═══════════════════════════════════════════════════════

  @impl true
  def handle_info(:flush_to_disk, state) do
    flush_dirty(state)
    schedule_flush()
    {:noreply, %{state | dirty_blocks: MapSet.new(), dirty_agents: MapSet.new()}}
  end

  # ═══════════════════════════════════════════════════════
  # ETS Helpers
  # ═══════════════════════════════════════════════════════

  defp get_recall(agent_name) do
    case :ets.lookup(@recall_table, agent_name) do
      [{^agent_name, entries}] -> entries
      [] -> []
    end
  end

  defp get_archival(agent_name) do
    case :ets.lookup(@archival_table, agent_name) do
      [{^agent_name, entries}] -> entries
      [] -> []
    end
  end

  # Accurate archival count -- if ETS is capped, count disk lines
  defp archival_count_with_disk(agent_name) do
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

  # For search: if ETS is at capacity, read full archive from disk
  defp get_archival_for_search(agent_name) do
    ets_entries = get_archival(agent_name)

    if length(ets_entries) >= @archival_ets_limit do
      # ETS is capped -- disk may have more. Read disk directly.
      archival_path = Path.join([data_dir(), "agents", agent_name, "archival.jsonl"])

      if File.exists?(archival_path) do
        load_jsonl(archival_path)
      else
        ets_entries
      end
    else
      ets_entries
    end
  end

  defp resolve_blocks(block_ids) do
    Enum.reduce(block_ids, [], fn id, acc ->
      case :ets.lookup(@blocks_table, id) do
        [{^id, block}] -> [block | acc]
        [] -> acc
      end
    end)
    |> Enum.reverse()
  end

  defp find_agent_block(agent_name, block_label) do
    case :ets.lookup(@agents_table, agent_name) do
      [{^agent_name, agent}] ->
        blocks = resolve_blocks(agent.block_ids)

        case Enum.find(blocks, &(&1.label == block_label)) do
          nil -> {:error, :block_not_found}
          block -> {:ok, block}
        end

      [] ->
        {:error, :agent_not_found}
    end
  end

  defp check_writable(block) do
    if block.read_only, do: {:error, :read_only}, else: :ok
  end

  # ═══════════════════════════════════════════════════════
  # Disk Persistence
  # ═══════════════════════════════════════════════════════

  defp load_from_disk do
    dir = data_dir()

    # Load blocks
    blocks_dir = Path.join(dir, "blocks")

    if File.dir?(blocks_dir) do
      case File.ls(blocks_dir) do
        {:ok, files} ->
          Enum.each(files, fn file ->
            if String.ends_with?(file, ".json") do
              path = Path.join(blocks_dir, file)
              load_block_file(path)
            end
          end)

        _ ->
          :ok
      end
    end

    # Load agents
    agents_dir = Path.join(dir, "agents")

    if File.dir?(agents_dir) do
      case File.ls(agents_dir) do
        {:ok, entries} ->
          Enum.each(entries, fn name ->
            agent_dir = Path.join(agents_dir, name)
            if File.dir?(agent_dir), do: load_agent_from_disk(name, agent_dir)
          end)

        _ ->
          :ok
      end
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
        limit: data["limit"] || @default_block_limit,
        read_only: data["read_only"] || false,
        created_at: data["created_at"],
        updated_at: data["updated_at"]
      }

      :ets.insert(@blocks_table, {block.id, block})
    else
      _ -> Logger.warning("MemoryStore: failed to load block #{path}")
    end
  end

  defp load_agent_from_disk(name, agent_dir) do
    # Agent config
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

        :ets.insert(@agents_table, {name, agent})
      else
        _ -> Logger.warning("MemoryStore: corrupt agent.json for #{name}")
      end
    end

    # Recall memory
    recall_path = Path.join(agent_dir, "recall.jsonl")

    if File.exists?(recall_path) do
      entries = load_jsonl(recall_path)
      :ets.insert(@recall_table, {name, Enum.reverse(entries) |> Enum.take(@recall_limit)})
    end

    # Archival memory -- only load most recent entries into ETS
    archival_path = Path.join(agent_dir, "archival.jsonl")

    if File.exists?(archival_path) do
      entries = load_jsonl(archival_path) |> Enum.take(@archival_ets_limit)
      :ets.insert(@archival_table, {name, entries})
    end

    Logger.debug("MemoryStore: loaded agent #{name}")
  end

  defp load_jsonl(path) do
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

  defp flush_dirty(state) do
    dir = data_dir()

    # Flush dirty blocks
    blocks_dir = Path.join(dir, "blocks")

    if MapSet.size(state.dirty_blocks) > 0 do
      File.mkdir_p!(blocks_dir)

      Enum.each(state.dirty_blocks, fn block_id ->
        path = Path.join(blocks_dir, "#{block_id}.json")

        case :ets.lookup(@blocks_table, block_id) do
          [{^block_id, block}] ->
            File.write!(path, Jason.encode!(block, pretty: true))

          [] ->
            # Block was deleted
            if File.exists?(path), do: File.rm(path)
        end
      end)
    end

    # Flush dirty agents
    Enum.each(state.dirty_agents, fn agent_name ->
      agent_dir = Path.join([dir, "agents", agent_name])
      File.mkdir_p!(agent_dir)

      # Agent config
      case :ets.lookup(@agents_table, agent_name) do
        [{^agent_name, agent}] ->
          config_path = Path.join(agent_dir, "agent.json")
          File.write!(config_path, Jason.encode!(agent, pretty: true))

        [] ->
          :ok
      end

      # Recall
      recall = get_recall(agent_name)

      if recall != [] do
        recall_path = Path.join(agent_dir, "recall.jsonl")
        lines = recall |> Enum.reverse() |> Enum.map_join("\n", &Jason.encode!/1)
        File.write!(recall_path, lines <> "\n")
      end

      # Archival -- append-only to preserve entries evicted from ETS.
      # Read existing disk IDs, write only entries not already on disk.
      archival = get_archival(agent_name)

      if archival != [] do
        archival_path = Path.join(agent_dir, "archival.jsonl")

        existing_ids =
          if File.exists?(archival_path) do
            archival_path
            |> File.stream!()
            |> Stream.map(&String.trim/1)
            |> Stream.reject(&(&1 == ""))
            |> Stream.map(&Jason.decode/1)
            |> Stream.filter(fn {:ok, _} -> true; _ -> false end)
            |> Stream.map(fn {:ok, d} -> d["id"] end)
            |> MapSet.new()
          else
            MapSet.new()
          end

        new_entries = Enum.reject(archival, fn e -> MapSet.member?(existing_ids, e.id) end)

        if new_entries != [] do
          append_lines = new_entries |> Enum.reverse() |> Enum.map_join("\n", &Jason.encode!/1)
          File.write!(archival_path, append_lines <> "\n", [:append])
        end
      end
    end)
  rescue
    e -> Logger.warning("MemoryStore: flush failed: #{inspect(e)}")
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

  # ═══════════════════════════════════════════════════════
  # Utilities
  # ═══════════════════════════════════════════════════════

  defp schedule_flush, do: Process.send_after(self(), :flush_to_disk, 10_000)

  defp generate_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

  defp now_iso, do: DateTime.to_iso8601(DateTime.utc_now())

  defp maybe_put(map, changes, key) do
    str_key = to_string(key)

    cond do
      Map.has_key?(changes, key) -> Map.put(map, key, Map.get(changes, key))
      Map.has_key?(changes, str_key) -> Map.put(map, key, Map.get(changes, str_key))
      true -> map
    end
  end

  defp broadcast_block_change(block_id, label) do
    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "memory:blocks",
      {:block_changed, block_id, label}
    )
  end

  defp broadcast_agent_change(agent_name, event) do
    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "memory:#{agent_name}",
      {:memory_changed, agent_name, event}
    )
  end
end
