defmodule MemoryStore do
  @moduledoc """
  A three-tier memory system for long-running agents.

  Modelled on Letta's memory design, with no vector database and no external
  services — ETS for hot reads, JSON and JSONL files for durability.

  ## The three tiers

  **Core memory** — named blocks pinned into the agent's context, the working
  set it always sees. Each block has a `label`, a `description` telling the
  agent what the block is for, a `value`, a character `limit`, and a
  `read_only` flag. Blocks are addressed by id and can be attached to several
  agents at once, so a shared "organization" block stays consistent across all
  of them.

  **Recall memory** — the conversation log, newest first, searchable by
  substring or date range. ETS keeps the most recent
  `MemoryStore.Config.recall_limit/0` entries; the rest stay on disk.

  **Archival memory** — an unbounded store of tagged passages the agent writes
  and searches deliberately. Search is keyword-based. Once ETS is full, searches
  read the JSONL file so older passages remain findable.

  ## Persistence

  Writes land in ETS immediately and are flushed to disk on a timer
  (`MemoryStore.Config.flush_interval_ms/0`), and again on clean shutdown. Only
  records touched since the last flush are rewritten. A hard kill can lose up to
  one interval of writes — call `flush/0` if you need a durability point.

  ## Singleton

  One named process backed by named ETS tables, configured through application
  env rather than per-instance options. See `MemoryStore.Config`.

      children = [MemoryStore]

  ## Example

      {:ok, _} = MemoryStore.create_agent("scout", [
        %{label: "persona", value: "You survey codebases."},
        %{label: "human", value: "Prefers terse answers."}
      ])

      {:ok, _} = MemoryStore.memory_rethink("scout", "human", "Prefers detail.")
      {:ok, text} = MemoryStore.compile_memory("scout")

      {:ok, _} = MemoryStore.archival_memory_insert("scout", "Repo uses Ash.", ["stack"])
      {:ok, hits} = MemoryStore.archival_memory_search("scout", "ash")
  """

  use GenServer

  alias MemoryStore.Config
  alias MemoryStore.Persistence
  alias MemoryStore.Storage

  @doc "Start the store. Configuration comes from application env, not `opts`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  # Blocks

  @doc """
  Create a standalone block.

  Accepts `:label`, `:value`, `:description`, `:limit`, and `:read_only`, with
  atom or string keys.
  """
  @spec create_block(map()) :: {:ok, map()} | {:error, :max_blocks_reached}
  def create_block(attrs), do: GenServer.call(__MODULE__, {:create_block, attrs})

  @doc "Fetch a block by id."
  @spec get_block(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_block(block_id), do: GenServer.call(__MODULE__, {:get_block, block_id})

  @doc "Update a block's `:value`, `:description`, or `:limit`."
  @spec update_block(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_block(block_id, changes),
    do: GenServer.call(__MODULE__, {:update_block, block_id, changes})

  @doc "Delete a block and detach it from every agent holding it."
  @spec delete_block(String.t()) :: :ok
  def delete_block(block_id), do: GenServer.call(__MODULE__, {:delete_block, block_id})

  @doc "List blocks, optionally filtered by `:label`."
  @spec list_blocks(keyword()) :: {:ok, [map()]}
  def list_blocks(opts \\ []), do: GenServer.call(__MODULE__, {:list_blocks, opts})

  # Agents

  @doc """
  Create an agent.

  `memory_blocks` are created fresh; `block_ids` attach existing shared blocks.
  Ordering is preserved: new blocks first, then the attached ids.
  """
  @spec create_agent(String.t(), [map()], [String.t()]) ::
          {:ok, map()} | {:error, :already_exists | :max_agents_reached}
  def create_agent(name, memory_blocks \\ [], block_ids \\ []),
    do: GenServer.call(__MODULE__, {:create_agent, name, memory_blocks, block_ids})

  @doc "Fetch an agent record and its block ids."
  @spec get_agent(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_agent(name), do: GenServer.call(__MODULE__, {:get_agent, name})

  @doc "Attach an existing block to an agent. Idempotent."
  @spec attach_block(String.t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def attach_block(agent_name, block_id),
    do: GenServer.call(__MODULE__, {:attach_block, agent_name, block_id})

  @doc "Detach a block from an agent without deleting the block."
  @spec detach_block(String.t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def detach_block(agent_name, block_id),
    do: GenServer.call(__MODULE__, {:detach_block, agent_name, block_id})

  @doc "List agents, each with its block labels and recall/archival counts."
  @spec list_agents() :: {:ok, [map()]}
  def list_agents, do: GenServer.call(__MODULE__, :list_agents)

  @doc "An agent's core memory as structured data."
  @spec read_core_memory(String.t()) :: {:ok, map()} | {:error, :not_found}
  def read_core_memory(agent_name),
    do: GenServer.call(__MODULE__, {:read_core_memory, agent_name})

  @doc "An agent's core memory rendered for injection into a system prompt."
  @spec compile_memory(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def compile_memory(agent_name), do: GenServer.call(__MODULE__, {:compile_memory, agent_name})

  # Agent-facing memory tools

  @doc """
  Replace the first occurrence of `old_text` in a block.

  Returns `{:error, :text_not_found}` when the text is absent, rather than
  silently doing nothing — an agent editing memory needs to know its edit
  missed.
  """
  @spec memory_replace(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def memory_replace(agent_name, block_label, old_text, new_text),
    do: GenServer.call(__MODULE__, {:memory_replace, agent_name, block_label, old_text, new_text})

  @doc """
  Insert `text` as a new line at `position` in a block.

  The position is clamped to the block's line count, so an out-of-range
  insert appends instead of failing.
  """
  @spec memory_insert(String.t(), String.t(), non_neg_integer(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def memory_insert(agent_name, block_label, position, text),
    do: GenServer.call(__MODULE__, {:memory_insert, agent_name, block_label, position, text})

  @doc "Rewrite a block's value entirely."
  @spec memory_rethink(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def memory_rethink(agent_name, block_label, new_value),
    do: GenServer.call(__MODULE__, {:memory_rethink, agent_name, block_label, new_value})

  # Recall

  @doc "Append a message to recall memory."
  @spec add_recall(String.t(), atom(), String.t(), map()) :: {:ok, map()}
  def add_recall(agent_name, role, content, metadata \\ %{}),
    do: GenServer.call(__MODULE__, {:add_recall, agent_name, role, content, metadata})

  @doc "Search recall memory by substring. Supports `:limit` and `:page`."
  @spec conversation_search(String.t(), String.t(), keyword()) :: {:ok, [map()]}
  def conversation_search(agent_name, query, opts \\ []),
    do: GenServer.call(__MODULE__, {:conversation_search, agent_name, query, opts})

  @doc """
  Search recall memory by date range, inclusive at both ends.

  Bounds may be `DateTime` structs or ISO-8601 strings.
  """
  @spec conversation_search_date(
          String.t(),
          DateTime.t() | String.t(),
          DateTime.t() | String.t(),
          keyword()
        ) :: {:ok, [map()]}
  def conversation_search_date(agent_name, start_date, end_date, opts \\ []) do
    GenServer.call(
      __MODULE__,
      {:conversation_search_date, agent_name, to_iso(start_date), to_iso(end_date), opts}
    )
  end

  # Archival

  @doc "Insert a passage into archival memory."
  @spec archival_memory_insert(String.t(), String.t(), [String.t()]) :: {:ok, map()}
  def archival_memory_insert(agent_name, content, tags \\ []),
    do: GenServer.call(__MODULE__, {:archival_insert, agent_name, content, tags})

  @doc "Search archival memory by keyword. Supports `:tags`, `:limit`, and `:page`."
  @spec archival_memory_search(String.t(), String.t(), keyword()) :: {:ok, [map()]}
  def archival_memory_search(agent_name, query, opts \\ []),
    do: GenServer.call(__MODULE__, {:archival_search, agent_name, query, opts})

  @doc "Delete an archival passage by id."
  @spec archival_memory_delete(String.t(), String.t()) :: :ok
  def archival_memory_delete(agent_name, passage_id),
    do: GenServer.call(__MODULE__, {:archival_delete, agent_name, passage_id})

  @doc "List archival passages with `:limit` and `:page`, plus the total count."
  @spec archival_memory_list(String.t(), keyword()) :: {:ok, map()}
  def archival_memory_list(agent_name, opts \\ []),
    do: GenServer.call(__MODULE__, {:archival_list, agent_name, opts})

  # Operations

  @doc """
  Flush pending writes to disk now and return once they have landed.

  Use before a checkpoint or a deliberate shutdown; the timer and `terminate/2`
  cover the ordinary cases.
  """
  @spec flush() :: :ok
  def flush, do: GenServer.call(__MODULE__, :flush)

  @doc "The directory memory is persisted to."
  @spec data_dir() :: String.t()
  def data_dir, do: Storage.data_dir()

  # Server

  @impl true
  def init(_opts) do
    # Trap exits so a supervisor shutdown runs terminate/2 and flushes, rather
    # than dropping everything written since the last timer tick.
    Process.flag(:trap_exit, true)

    Enum.each(Storage.tables(), &:ets.new(&1, [:named_table, :public, :set]))
    Persistence.load_from_disk()
    schedule_flush()

    {:ok, %{dirty_blocks: MapSet.new(), dirty_agents: MapSet.new()}}
  end

  @impl true
  def handle_call({:create_block, attrs}, _from, state) do
    if Storage.max_blocks_reached?() do
      {:reply, {:error, :max_blocks_reached}, state}
    else
      {:ok, block} = Storage.create_block(attrs)
      {:reply, {:ok, block}, dirty_block(state, block.id)}
    end
  end

  def handle_call({:get_block, block_id}, _from, state),
    do: {:reply, Storage.get_block(block_id), state}

  def handle_call({:update_block, block_id, changes}, _from, state) do
    case Storage.update_block(block_id, changes) do
      {:ok, updated} -> {:reply, {:ok, updated}, dirty_block(state, block_id)}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:delete_block, block_id}, _from, state) do
    {dirtied_agents, :ok} = Storage.delete_block(block_id)

    new_state =
      state
      |> dirty_block(block_id)
      |> Map.update!(:dirty_agents, &Enum.into(dirtied_agents, &1))

    {:reply, :ok, new_state}
  end

  def handle_call({:list_blocks, opts}, _from, state),
    do: {:reply, {:ok, Storage.list_blocks(opts)}, state}

  def handle_call({:create_agent, name, memory_blocks, extra_block_ids}, _from, state) do
    cond do
      Storage.max_agents_reached?() ->
        {:reply, {:error, :max_agents_reached}, state}

      Storage.agent_exists?(name) ->
        {:reply, {:error, :already_exists}, state}

      true ->
        {created_ids, dirty} = Storage.create_blocks(memory_blocks)
        now = now_iso()

        agent = %{
          name: name,
          block_ids: created_ids ++ extra_block_ids,
          created_at: now,
          updated_at: now
        }

        {:ok, _} = Storage.insert_agent(agent)
        notify(:agent_created, name, %{agent_name: name})

        new_state = %{
          state
          | dirty_blocks: MapSet.union(state.dirty_blocks, dirty),
            dirty_agents: MapSet.put(state.dirty_agents, name)
        }

        {:reply, {:ok, agent}, new_state}
    end
  end

  def handle_call({:get_agent, name}, _from, state),
    do: {:reply, Storage.get_agent(name), state}

  def handle_call({:attach_block, agent_name, block_id}, _from, state) do
    with {:ok, agent} <- Storage.get_agent(agent_name),
         {:ok, _block} <- Storage.get_block(block_id) do
      if block_id in agent.block_ids do
        {:reply, {:ok, agent}, state}
      else
        updated = %{agent | block_ids: agent.block_ids ++ [block_id], updated_at: now_iso()}
        {:ok, _} = Storage.insert_agent(updated)
        {:reply, {:ok, updated}, dirty_agent(state, agent_name)}
      end
    else
      _ -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:detach_block, agent_name, block_id}, _from, state) do
    case Storage.get_agent(agent_name) do
      {:ok, agent} ->
        updated = %{
          agent
          | block_ids: List.delete(agent.block_ids, block_id),
            updated_at: now_iso()
        }

        {:ok, _} = Storage.insert_agent(updated)
        {:reply, {:ok, updated}, dirty_agent(state, agent_name)}

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:list_agents, _from, state) do
    agents =
      Enum.map(Storage.list_agents(), fn agent ->
        labels = agent.block_ids |> Storage.resolve_blocks() |> Enum.map(& &1.label)

        Map.merge(agent, %{
          block_labels: labels,
          recall_count: length(Storage.get_recall(agent.name)),
          archival_count: Storage.count_archival(agent.name)
        })
      end)

    {:reply, {:ok, agents}, state}
  end

  def handle_call({:read_core_memory, agent_name}, _from, state) do
    case Storage.get_agent(agent_name) do
      {:ok, agent} ->
        blocks =
          agent.block_ids
          |> Storage.resolve_blocks()
          |> Enum.map(&Map.take(&1, [:label, :description, :value, :read_only]))

        result = %{
          agent: agent_name,
          blocks: blocks,
          recall_count: length(Storage.get_recall(agent_name)),
          archival_count: Storage.count_archival(agent_name)
        }

        {:reply, {:ok, result}, state}

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:compile_memory, agent_name}, _from, state) do
    case Storage.get_agent(agent_name) do
      {:ok, agent} ->
        compiled = agent.block_ids |> Storage.resolve_blocks() |> Storage.compile_blocks()
        {:reply, {:ok, compiled}, state}

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:memory_replace, agent_name, label, old_text, new_text}, _from, state) do
    with_writable_block(agent_name, label, state, fn block ->
      if String.contains?(block.value, old_text) do
        Storage.save_block_value(
          block,
          String.replace(block.value, old_text, new_text, global: false)
        )
      else
        {:error, :text_not_found}
      end
    end)
  end

  def handle_call({:memory_insert, agent_name, label, position, text}, _from, state) do
    with_writable_block(agent_name, label, state, fn block ->
      lines = String.split(block.value, "\n")
      {before, rest} = Enum.split(lines, min(max(position, 0), length(lines)))
      Storage.save_block_value(block, Enum.join(before ++ [text] ++ rest, "\n"))
    end)
  end

  def handle_call({:memory_rethink, agent_name, label, new_value}, _from, state) do
    with_writable_block(agent_name, label, state, &Storage.save_block_value(&1, new_value))
  end

  def handle_call({:add_recall, agent_name, role, content, metadata}, _from, state) do
    {:ok, entry} = Storage.add_recall(agent_name, role, content, metadata)
    {:reply, {:ok, entry}, dirty_agent(state, agent_name)}
  end

  def handle_call({:conversation_search, agent_name, query, opts}, _from, state),
    do: {:reply, {:ok, Storage.search_recall(agent_name, query, opts)}, state}

  def handle_call({:conversation_search_date, agent_name, from, to, opts}, _from, state),
    do: {:reply, {:ok, Storage.search_recall_by_date(agent_name, from, to, opts)}, state}

  def handle_call({:archival_insert, agent_name, content, tags}, _from, state) do
    {:ok, passage} = Storage.insert_archival(agent_name, content, tags)
    notify(:archival_insert, agent_name, %{agent_name: agent_name, passage_id: passage.id})
    {:reply, {:ok, passage}, dirty_agent(state, agent_name)}
  end

  def handle_call({:archival_search, agent_name, query, opts}, _from, state),
    do: {:reply, {:ok, Storage.search_archival(agent_name, query, opts)}, state}

  def handle_call({:archival_delete, agent_name, passage_id}, _from, state) do
    :ok = Storage.delete_archival(agent_name, passage_id)
    {:reply, :ok, dirty_agent(state, agent_name)}
  end

  def handle_call({:archival_list, agent_name, opts}, _from, state),
    do: {:reply, {:ok, Storage.list_archival(agent_name, opts)}, state}

  def handle_call(:flush, _from, state) do
    Persistence.flush_dirty(state)
    {:reply, :ok, clear_dirty(state)}
  end

  @impl true
  def handle_info(:flush_to_disk, state) do
    Persistence.flush_dirty(state)
    schedule_flush()
    {:noreply, clear_dirty(state)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Persistence.flush_dirty(state)
    :ok
  end

  # Private

  defp with_writable_block(agent_name, label, state, fun) do
    with {:ok, block} <- Storage.find_agent_block(agent_name, label),
         :ok <- Storage.writable?(block),
         {:ok, updated} <- fun.(block) do
      {:reply, {:ok, updated}, dirty_block(state, block.id)}
    else
      error -> {:reply, error, state}
    end
  end

  defp notify(event, agent_name, payload),
    do: Config.notifier().notify(event, agent_name, payload)

  defp dirty_block(state, id),
    do: %{state | dirty_blocks: MapSet.put(state.dirty_blocks, id)}

  defp dirty_agent(state, name),
    do: %{state | dirty_agents: MapSet.put(state.dirty_agents, name)}

  defp clear_dirty(state),
    do: %{state | dirty_blocks: MapSet.new(), dirty_agents: MapSet.new()}

  defp schedule_flush,
    do: Process.send_after(self(), :flush_to_disk, Config.flush_interval_ms())

  defp to_iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp to_iso(s) when is_binary(s), do: s

  defp now_iso, do: DateTime.to_iso8601(DateTime.utc_now())
end
