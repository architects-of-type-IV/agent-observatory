defmodule Ichor.EventBuffer do
  @moduledoc """
  In-memory event buffer. Accepts events via `ingest/1` and returns
  immediately. No SQLite -- everything is ETS + PubSub.

  Also owns payload sanitization and tool duration tracking.

  Session aliases: when an event arrives with both a raw UUID and a tmux_session,
  the mapping is cached. Late events (e.g., SessionEnd after tmux kill) that arrive
  with only the UUID are resolved via that cache.

  Tombstones: `remove_session/1` places a 30s tombstone. Events resolving to a
  tombstoned session are silently dropped (prevents ghost agents after shutdown).
  """
  use GenServer

  alias Ichor.Gateway.AgentRegistry.AgentEntry

  @table :event_buffer_events
  @tools :ichor_tool_starts
  @aliases :ichor_session_aliases
  @tombstones :ichor_session_tombstones
  @max_events 5_000
  @tombstone_ttl_ms 30_000

  # ── Public API ──────────────────────────────────────────────────

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Ingest a hook event. Drops events for tombstoned sessions."
  def ingest(event_attrs) when is_map(event_attrs) do
    event =
      event_attrs
      |> Map.update(:payload, %{}, &sanitize_payload/1)
      |> put_duration()
      |> track_tool_start()
      |> build_event()

    unless tombstoned?(event.session_id) do
      :ets.insert(@table, {event.id, event})
      maybe_evict()
    end

    {:ok, event}
  end

  @doc "Get all events from the buffer (most recent first)."
  def list_events do
    @table
    |> :ets.tab2list()
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  @doc "Remove all events for a session and tombstone it."
  def remove_session(session_id) do
    @table
    |> :ets.tab2list()
    |> Enum.each(fn
      {id, %{session_id: ^session_id}} -> :ets.delete(@table, id)
      _ -> :ok
    end)

    tombstone_session(session_id)
  end

  @doc "Place a 30s tombstone to reject late events without purging existing ones."
  def tombstone_session(session_id) do
    :ets.insert(@tombstones, {session_id, System.monotonic_time(:millisecond)})
    :ok
  end

  @doc "Get events for a specific session."
  def events_for_session(session_id) do
    @table
    |> :ets.tab2list()
    |> Enum.map(&elem(&1, 1))
    |> Enum.filter(&(&1.session_id == session_id))
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  # ── GenServer ─────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    Enum.each([@table, @tools, @aliases, @tombstones], &ensure_ets/1)
    {:ok, %{}}
  end

  # ── Internals ─────────────────────────────────────────────────

  defp ensure_ets(name) do
    case :ets.whereis(name) do
      :undefined ->
        try do
          :ets.new(name, [:named_table, :public, :set])
        rescue
          ArgumentError -> :ok
        end

      _ ->
        :ok
    end
  end

  defp maybe_evict do
    size = :ets.info(@table, :size)

    if size > @max_events do
      @table
      |> :ets.tab2list()
      |> Enum.sort_by(fn {_id, e} -> e.inserted_at end, {:asc, DateTime})
      |> Enum.take(size - @max_events)
      |> Enum.each(fn {id, _} -> :ets.delete(@table, id) end)
    end
  end

  # ── Tombstones ────────────────────────────────────────────────

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

  # ── Session ID Resolution ─────────────────────────────────────

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

  # ── Payload Sanitization ──────────────────────────────────────

  defp sanitize_payload(payload) when is_map(payload) do
    payload
    |> Map.delete("tool_response")
    |> truncate_tool_input()
  end

  defp sanitize_payload(payload), do: payload

  defp truncate_tool_input(%{"tool_input" => input} = payload) when is_map(input) do
    truncated =
      Map.new(input, fn
        {k, v} when is_binary(v) and byte_size(v) > 500 ->
          {k, String.slice(v, 0, 500) <> "...[truncated]"}

        pair ->
          pair
      end)

    Map.put(payload, "tool_input", truncated)
  end

  defp truncate_tool_input(payload), do: payload

  # ── Tool Duration Tracking ────────────────────────────────────

  defp put_duration(%{hook_event_type: type, tool_use_id: id} = attrs)
       when type in ["PostToolUse", "PostToolUseFailure"] and is_binary(id) do
    case :ets.lookup(@tools, id) do
      [{^id, start_time}] ->
        :ets.delete(@tools, id)
        Map.put(attrs, :duration_ms, System.monotonic_time(:millisecond) - start_time)

      _ ->
        attrs
    end
  end

  defp put_duration(attrs), do: attrs

  defp track_tool_start(%{hook_event_type: "PreToolUse", tool_use_id: id} = attrs)
       when is_binary(id) do
    :ets.insert(@tools, {id, System.monotonic_time(:millisecond)})
    attrs
  end

  defp track_tool_start(attrs), do: attrs

  # ── Event Construction ────────────────────────────────────────

  defp build_event(attrs) do
    now = DateTime.utc_now()
    tmux_session = attrs[:tmux_session] || attrs["tmux_session"]
    raw_id = attrs[:session_id] || attrs["session_id"] || "unknown"

    %{
      id: Ash.UUID.generate(),
      source_app: attrs[:source_app] || attrs["source_app"] || "unknown",
      session_id: resolve_session_id(raw_id, tmux_session),
      hook_event_type: coerce_hook_type(attrs[:hook_event_type] || attrs["hook_event_type"]),
      payload: attrs[:payload] || attrs["payload"] || %{},
      summary: attrs[:summary] || attrs["summary"],
      model_name: attrs[:model_name] || attrs["model_name"],
      tool_name: attrs[:tool_name] || attrs["tool_name"],
      tool_use_id: attrs[:tool_use_id] || attrs["tool_use_id"],
      cwd: attrs[:cwd] || attrs["cwd"],
      permission_mode: attrs[:permission_mode] || attrs["permission_mode"],
      duration_ms: attrs[:duration_ms] || attrs["duration_ms"],
      tmux_session: tmux_session,
      inserted_at: now,
      updated_at: now
    }
  end

  defp coerce_hook_type(t) when is_atom(t), do: t

  defp coerce_hook_type(t) when is_binary(t) do
    try do
      String.to_existing_atom(t)
    rescue
      ArgumentError -> String.to_atom(t)
    end
  end

  defp coerce_hook_type(_), do: :Stop
end
