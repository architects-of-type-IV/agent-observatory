defmodule Ichor.EventBuffer do
  @moduledoc """
  In-memory event buffer. Accepts events via `ingest/1` and returns
  immediately. No SQLite -- everything is ETS + PubSub.

  Also owns payload sanitization and tool duration tracking.
  """
  use GenServer

  @events_table :event_buffer_events
  @tool_start_table :ichor_tool_starts
  @max_events 5_000

  # ── Public API ──────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Ingest a hook event. Sanitizes payload, computes tool duration,
  builds an event map, and stores in ETS.
  Returns {:ok, event} immediately.
  """
  def ingest(event_attrs) when is_map(event_attrs) do
    attrs =
      event_attrs
      |> Map.update(:payload, %{}, &sanitize_payload/1)
      |> put_duration()
      |> track_tool_start()

    event = build_event(attrs)
    ensure_table()
    :ets.insert(@events_table, {event.id, event})
    maybe_evict()
    {:ok, event}
  end

  @doc "Get all events from the buffer (most recent first)."
  def list_events do
    ensure_table()

    @events_table
    |> :ets.tab2list()
    |> Enum.map(fn {_id, event} -> event end)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  @doc "Remove all events for a session from the buffer."
  def remove_session(session_id) do
    ensure_table()

    @events_table
    |> :ets.tab2list()
    |> Enum.filter(fn {_id, event} -> event.session_id == session_id end)
    |> Enum.each(fn {id, _event} -> :ets.delete(@events_table, id) end)

    :ok
  end

  @doc "Get events for a specific session."
  def events_for_session(session_id) do
    ensure_table()

    @events_table
    |> :ets.tab2list()
    |> Enum.map(fn {_id, event} -> event end)
    |> Enum.filter(&(&1.session_id == session_id))
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  # ── GenServer Callbacks ─────────────────────────────────────────

  @impl true
  def init(_opts) do
    ensure_table()
    ensure_tool_table()
    {:ok, %{}}
  end

  defp ensure_table do
    case :ets.whereis(@events_table) do
      :undefined ->
        try do
          :ets.new(@events_table, [:named_table, :public, :set])
        rescue
          ArgumentError -> :ok
        end

      _ ->
        :ok
    end
  end

  defp maybe_evict do
    size = :ets.info(@events_table, :size)

    if size > @max_events do
      # Drop oldest entries to stay under cap
      @events_table
      |> :ets.tab2list()
      |> Enum.map(fn {id, event} -> {id, event.inserted_at} end)
      |> Enum.sort_by(&elem(&1, 1), {:asc, DateTime})
      |> Enum.take(size - @max_events)
      |> Enum.each(fn {id, _} -> :ets.delete(@events_table, id) end)
    end
  end

  # ── Payload Sanitization ────────────────────────────────────────

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

  defp ensure_tool_table do
    case :ets.whereis(@tool_start_table) do
      :undefined ->
        try do
          :ets.new(@tool_start_table, [:named_table, :public, :set])
        rescue
          ArgumentError -> :ok
        end

      _ ->
        :ok
    end
  end

  defp put_duration(attrs) do
    hook_type = attrs[:hook_event_type]
    tool_use_id = attrs[:tool_use_id]

    duration = compute_duration(hook_type, tool_use_id)
    Map.put(attrs, :duration_ms, duration || attrs[:duration_ms])
  end

  defp compute_duration(hook_type, tool_use_id)
       when hook_type in ["PostToolUse", "PostToolUseFailure"] and is_binary(tool_use_id) do
    ensure_tool_table()

    case :ets.lookup(@tool_start_table, tool_use_id) do
      [{^tool_use_id, start_time}] ->
        :ets.delete(@tool_start_table, tool_use_id)
        System.monotonic_time(:millisecond) - start_time

      _ ->
        nil
    end
  end

  defp compute_duration(_, _), do: nil

  defp track_tool_start(attrs) do
    if attrs[:hook_event_type] == "PreToolUse" && attrs[:tool_use_id] do
      ensure_tool_table()
      :ets.insert(@tool_start_table, {attrs[:tool_use_id], System.monotonic_time(:millisecond)})
    end

    attrs
  end

  # ── Event Construction ─────────────────────────────────────────

  defp build_event(attrs) do
    now = DateTime.utc_now()

    hook_type =
      case attrs[:hook_event_type] || attrs["hook_event_type"] do
        t when is_atom(t) -> t
        t when is_binary(t) ->
          try do
            String.to_existing_atom(t)
          rescue
            ArgumentError -> String.to_atom(t)
          end
        _ -> :Stop
      end

    tmux_session = attrs[:tmux_session] || attrs["tmux_session"]
    raw_session_id = attrs[:session_id] || attrs["session_id"] || "unknown"
    session_id = resolve_session_id(raw_session_id, tmux_session)

    %{
      id: Ash.UUID.generate(),
      source_app: attrs[:source_app] || attrs["source_app"] || "unknown",
      session_id: session_id,
      hook_event_type: hook_type,
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

  # tmux session name is the canonical identity. No BEAM process check needed —
  # if the event says it came from a tmux session, that's the ID. Period.
  defp resolve_session_id(raw_id, nil), do: raw_id
  defp resolve_session_id(raw_id, ""), do: raw_id
  defp resolve_session_id(_raw_id, tmux_session), do: tmux_session
end
