defmodule Observatory.EventBuffer do
  @moduledoc """
  In-memory event buffer. Accepts events via `ingest/1` and returns
  immediately. No SQLite -- everything is ETS + PubSub.
  """
  use GenServer

  @events_table :event_buffer_events
  @max_events 5_000

  # ── Public API ──────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Ingest a hook event. Builds an event map and stores in ETS.
  Returns {:ok, event} immediately.
  """
  def ingest(event_attrs) when is_map(event_attrs) do
    event = build_event(event_attrs)
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
    init_table()
    {:ok, %{}}
  end

  # ── Private ─────────────────────────────────────────────────────

  defp init_table do
    ensure_table()
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

    %{
      id: Ash.UUID.generate(),
      source_app: attrs[:source_app] || attrs["source_app"] || "unknown",
      session_id: attrs[:session_id] || attrs["session_id"] || "unknown",
      hook_event_type: hook_type,
      payload: attrs[:payload] || attrs["payload"] || %{},
      summary: attrs[:summary] || attrs["summary"],
      model_name: attrs[:model_name] || attrs["model_name"],
      tool_name: attrs[:tool_name] || attrs["tool_name"],
      tool_use_id: attrs[:tool_use_id] || attrs["tool_use_id"],
      cwd: attrs[:cwd] || attrs["cwd"],
      permission_mode: attrs[:permission_mode] || attrs["permission_mode"],
      duration_ms: attrs[:duration_ms] || attrs["duration_ms"],
      tmux_session: attrs[:tmux_session] || attrs["tmux_session"],
      inserted_at: now,
      updated_at: now
    }
  end
end
