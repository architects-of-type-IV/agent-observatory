defmodule Ichor.Signals.EventStream do
  @moduledoc """
  Unified event runtime. Canonical owner of the in-memory event buffer,
  session aliases, tombstones, tool duration tracking, and heartbeat liveness.

  Public API:
  - `ingest_raw/1`           -- normalize a raw hook map, store, and emit signals
  - `record_heartbeat/2`     -- normalize a heartbeat into a trace event, update liveness
  - `publish_fact/2`         -- publish an internal fact (watchdog probes, etc.)
  - `subscribe/2`            -- subscribe to the normalized event stream
  - `latest_session_state/1` -- liveness/alias/last-seen for a session
  - `list_events/0`          -- all buffered events (most recent first)
  - `latest_per_session/0`   -- latest event per session (dashboard seed)
  - `unique_project_cwds/0`  -- unique non-empty cwd values across buffer
  - `events_for_session/1`   -- events for a specific session
  - `remove_session/1`       -- remove session events and tombstone
  - `tombstone_session/1`    -- place a 30s tombstone (drops late events)
  """

  use GenServer

  require Logger

  alias Ichor.Signals
  alias Ichor.Signals.EventStream.{AgentLifecycle, Normalizer}
  alias Ichor.Workshop.AgentEntry

  # ETS table names (preserved for compatibility)
  @table :event_buffer_events
  @tools :ichor_tool_starts
  @aliases :ichor_session_aliases
  @tombstones :ichor_session_tombstones
  @max_events 5_000
  @tombstone_ttl_ms 30_000

  # Heartbeat constants
  @eviction_threshold_seconds 90
  @check_interval_ms 30_000

  @doc "Ingest a raw hook event map. Normalizes, stores, emits signals, and runs side effects."
  @spec ingest_raw(map()) :: {:ok, map()}
  def ingest_raw(raw_map) when is_map(raw_map) do
    {:ok, event} = ingest(raw_map)

    unless tombstoned?(event.session_id) do
      Signals.emit(:new_event, %{event: event})
      ingest_event(event)
    end

    {:ok, event}
  end

  @doc "Record a heartbeat for `agent_id` within `cluster_id`."
  @spec record_heartbeat(String.t(), String.t()) :: :ok
  def record_heartbeat(agent_id, cluster_id)
      when is_binary(agent_id) and is_binary(cluster_id) do
    GenServer.call(__MODULE__, {:heartbeat, agent_id, cluster_id})
  end

  @doc "Publish an internal fact (watchdog probes, system events, etc.)."
  @spec publish_fact(atom(), map()) :: :ok
  def publish_fact(name, attrs \\ %{}) when is_atom(name) and is_map(attrs) do
    Signals.emit(:new_event, %{name: name, attrs: attrs})
    :ok
  end

  @doc "Subscribe to the normalized event stream. Delegates to Signals."
  @spec subscribe(atom(), keyword()) :: :ok | {:error, term()}
  def subscribe(topic, opts \\ []) when is_atom(topic) do
    case Keyword.get(opts, :scope_id) do
      nil -> Signals.subscribe(topic)
      scope_id -> Signals.subscribe(topic, scope_id)
    end
  end

  @doc "Returns liveness metadata for a session from the heartbeat store."
  @spec latest_session_state(String.t()) :: map() | nil
  def latest_session_state(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:get_session_state, session_id})
  end

  # Public API -- event buffer reads (ETS, no GenServer round-trip)

  @doc "Ingest a hook event map into the ETS buffer. Drops events for tombstoned sessions."
  @spec ingest(map()) :: {:ok, map()}
  def ingest(event_attrs) when is_map(event_attrs) do
    sanitized = Map.update(event_attrs, :payload, %{}, &Normalizer.sanitize_payload/1)

    attrs_with_duration =
      case lookup_tool_start(sanitized) do
        {id, start_time} ->
          :ets.delete(@tools, id)
          Normalizer.put_duration(sanitized, start_time)

        nil ->
          sanitized
      end

    attrs_tracked = track_tool_start(attrs_with_duration)

    tmux_session = Normalizer.get_field(attrs_tracked, :tmux_session)
    raw_id = Normalizer.get_field(attrs_tracked, :session_id) || "unknown"
    resolved_session_id = resolve_session_id(raw_id, tmux_session)

    event = Normalizer.build_event(attrs_tracked, resolved_session_id)

    unless tombstoned?(event.session_id) do
      :ets.insert(@table, {event.id, event})
      maybe_evict()
    end

    {:ok, event}
  end

  @doc "Get all events from the buffer (most recent first)."
  @spec list_events() :: [map()]
  def list_events do
    :ets.tab2list(@table)
    |> Enum.sort_by(fn {_k, e} -> e.inserted_at end, {:desc, DateTime})
    |> Enum.map(&elem(&1, 1))
  end

  @doc "Get the latest event per session (lightweight seed for dashboard mount)."
  @spec latest_per_session() :: [map()]
  def latest_per_session do
    :ets.foldl(fn {_id, event}, acc -> keep_latest(acc, event) end, %{}, @table)
    |> Map.values()
  end

  @doc "Returns a MapSet of all unique non-empty cwd values from the event buffer."
  @spec unique_project_cwds() :: MapSet.t(String.t())
  def unique_project_cwds do
    :ets.foldl(
      fn
        {_id, %{cwd: cwd}}, acc when is_binary(cwd) and cwd != "" -> MapSet.put(acc, cwd)
        _, acc -> acc
      end,
      MapSet.new(),
      @table
    )
  end

  @doc "Get events for a specific session."
  @spec events_for_session(String.t()) :: [map()]
  def events_for_session(session_id) do
    match_spec = [{{:_, %{session_id: session_id}}, [], [:"$_"]}]

    @table
    |> :ets.select(match_spec)
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  @doc "Remove all events for a session and tombstone it."
  @spec remove_session(String.t()) :: :ok
  def remove_session(session_id) do
    :ets.select_delete(@table, [{{:_, %{session_id: session_id}}, [], [true]}])
    tombstone_session(session_id)
  end

  @doc "Place a 30s tombstone to reject late events without purging existing ones."
  @spec tombstone_session(String.t()) :: :ok
  def tombstone_session(session_id) do
    :ets.insert(@tombstones, {session_id, System.monotonic_time(:millisecond)})
    :ok
  end

  # GenServer lifecycle

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Enum.each([@table, @tools, @aliases, @tombstones], &ensure_ets/1)
    :timer.send_interval(@check_interval_ms, :check_heartbeats)
    Signals.subscribe(:fleet)
    {:ok, %{}}
  end

  @impl true
  def handle_call({:heartbeat, agent_id, cluster_id}, _from, state) do
    entry = %{last_seen: DateTime.utc_now(), cluster_id: cluster_id}
    {:reply, :ok, Map.put(state, agent_id, entry)}
  end

  @impl true
  def handle_call({:get_session_state, agent_id}, _from, state) do
    {:reply, Map.get(state, agent_id), state}
  end

  @impl true
  def handle_info(:check_heartbeats, state) do
    now = DateTime.utc_now()

    evicted_ids =
      state
      |> Enum.filter(fn {_id, %{last_seen: last_seen}} ->
        DateTime.diff(now, last_seen, :second) > @eviction_threshold_seconds
      end)
      |> Enum.map(fn {id, _entry} -> id end)

    Enum.each(evicted_ids, fn agent_id ->
      Signals.emit(:agent_evicted, %{session_id: agent_id})
      Logger.info("Evicted stale agent #{agent_id}")
    end)

    {:noreply, Map.drop(state, evicted_ids)}
  end

  @impl true
  def handle_info(
        %Ichor.Signals.Message{name: :agent_stopped, data: %{session_id: session_id}},
        state
      )
      when is_binary(session_id) do
    tombstone_session(session_id)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # Ingest pipeline

  defp ingest_event(event) do
    agent_id = AgentLifecycle.resolve_or_create_agent(event.session_id, event)
    maybe_emit_session_end(event.hook_event_type, agent_id)
    handle_channel_events(event)
    Signals.emit(:agent_event, agent_id, %{event: event})
    :ok
  end

  defp maybe_emit_session_end(:SessionEnd, agent_id),
    do: Signals.emit(:session_ended, %{session_id: agent_id, status: :ended})

  defp maybe_emit_session_end(_type, _agent_id), do: :ok

  defp handle_channel_events(%{hook_event_type: :SessionStart}), do: :ok

  defp handle_channel_events(%{hook_event_type: :PreToolUse} = event) do
    input = (event.payload || %{})["tool_input"] || %{}
    handle_pre_tool_use(event.tool_name, event, input)
  end

  defp handle_channel_events(_event), do: :ok

  defp handle_pre_tool_use("TeamCreate", _event, input),
    do: AgentLifecycle.handle_team_create(input)

  defp handle_pre_tool_use("TeamDelete", _event, input),
    do: AgentLifecycle.handle_team_delete(input)

  defp handle_pre_tool_use("SendMessage", event, input) do
    emit_intercepted(
      event,
      input["recipient"],
      input["content"] || input["summary"] || "",
      input["type"]
    )
  end

  defp handle_pre_tool_use("mcp__ichor__send_message", event, input) do
    emit_intercepted_mcp(event, input["input"] || %{})
  end

  defp handle_pre_tool_use(_tool_name, _event, _input), do: :ok

  defp emit_intercepted(event, recipient, content, type) do
    Signals.emit(:agent_message_intercepted, event.session_id, %{
      from: event.session_id,
      to: recipient,
      content: String.slice(content, 0, 200),
      type: type || "message"
    })
  end

  defp emit_intercepted_mcp(event, args) when is_map(args) do
    Signals.emit(:agent_message_intercepted, event.session_id, %{
      from: args["from_session_id"] || event.session_id,
      to: args["to_session_id"],
      content: String.slice(args["content"] || "", 0, 200),
      type: "message"
    })
  end

  defp emit_intercepted_mcp(_event, _args), do: :ok

  # ETS helpers -- session aliases and tool timing

  defp resolve_session_id(raw_id, tmux) when tmux in [nil, ""] do
    case {AgentEntry.uuid?(raw_id), :ets.lookup(@aliases, raw_id)} do
      {true, [{_, canonical}]} -> canonical
      _ -> raw_id
    end
  end

  defp resolve_session_id(raw_id, tmux_session) do
    if AgentEntry.uuid?(raw_id), do: :ets.insert(@aliases, {raw_id, tmux_session})
    tmux_session
  end

  defp lookup_tool_start(%{hook_event_type: type, tool_use_id: id})
       when type in ["PostToolUse", "PostToolUseFailure"] and is_binary(id) do
    case :ets.lookup(@tools, id) do
      [{^id, start_time}] -> {id, start_time}
      _ -> nil
    end
  end

  defp lookup_tool_start(_attrs), do: nil

  defp track_tool_start(%{hook_event_type: "PreToolUse", tool_use_id: id} = attrs)
       when is_binary(id) do
    :ets.insert(@tools, {id, System.monotonic_time(:millisecond)})
    attrs
  end

  defp track_tool_start(attrs), do: attrs

  # ETS buffer helpers

  defp keep_latest(acc, event) do
    sid = event.session_id

    case Map.get(acc, sid) do
      nil -> Map.put(acc, sid, event)
      prev -> if newer?(event, prev), do: Map.put(acc, sid, event), else: acc
    end
  end

  defp newer?(event, prev) do
    DateTime.compare(event.inserted_at, prev.inserted_at) == :gt
  end

  defp maybe_evict do
    size = :ets.info(@table, :size)

    if size > @max_events do
      evict_count = size - @max_events

      # Fold once to collect the N oldest entries without a full sort.
      # We maintain a max-heap of size `evict_count` by tracking the
      # worst (newest) candidate seen so far, replacing it when we find
      # something older.  For small evict_count (almost always 1) this
      # is O(n) with negligible constant vs. O(n log n) sort.
      :ets.foldl(
        fn {id, e}, acc -> evict_candidate(acc, id, e.inserted_at, evict_count) end,
        %{},
        @table
      )
      |> Map.keys()
      |> Enum.each(&:ets.delete(@table, &1))
    end
  end

  defp evict_candidate(acc, id, ts, evict_count) when map_size(acc) < evict_count do
    Map.put(acc, id, ts)
  end

  defp evict_candidate(acc, id, ts, _evict_count) do
    {newest_id, newest_ts} = Enum.max_by(acc, fn {_k, v} -> v end, DateTime)

    case DateTime.compare(ts, newest_ts) do
      :lt -> acc |> Map.delete(newest_id) |> Map.put(id, ts)
      _ -> acc
    end
  end

  defp tombstoned?(session_id) do
    case :ets.lookup(@tombstones, session_id) do
      [{_, placed_at}] ->
        if System.monotonic_time(:millisecond) - placed_at > @tombstone_ttl_ms do
          :ets.delete(@tombstones, session_id)
          false
        else
          true
        end

      [] ->
        false
    end
  end

  defp ensure_ets(name) do
    case :ets.whereis(name) do
      :undefined -> :ets.new(name, [:named_table, :public, :set])
      _ -> :ok
    end
  end
end
