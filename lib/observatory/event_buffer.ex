defmodule Observatory.EventBuffer do
  @moduledoc """
  Write-behind buffer for hook events. Accepts events via `ingest/1`,
  broadcasts immediately via PubSub, and flushes to SQLite in batches
  every 2 seconds. This decouples HTTP response time from DB write latency.
  """
  use GenServer
  require Logger

  @flush_interval_ms 2_000
  @buffer_table :event_buffer
  @max_buffer_size 500

  # ── Public API ──────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Ingest a hook event. Builds an event struct, broadcasts immediately,
  and queues the DB write for async batch flush.

  Returns {:ok, event} where event is a map with all expected fields.
  """
  def ingest(event_attrs) when is_map(event_attrs) do
    event = build_event(event_attrs)
    GenServer.cast(__MODULE__, {:buffer, event_attrs, event})
    {:ok, event}
  end

  # ── GenServer Callbacks ─────────────────────────────────────────

  @impl true
  def init(_opts) do
    init_table()
    schedule_flush()
    {:ok, %{flush_count: 0}}
  end

  @impl true
  def handle_cast({:buffer, event_attrs, event}, state) do
    # Buffer for async DB write
    :ets.insert(@buffer_table, {event.id, event_attrs, System.monotonic_time(:millisecond)})

    # Enforce max buffer size (drop oldest if exceeded)
    if :ets.info(@buffer_table, :size) > @max_buffer_size do
      case :ets.first(@buffer_table) do
        :"$end_of_table" -> :ok
        key -> :ets.delete(@buffer_table, key)
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:flush, state) do
    flushed = flush_buffer()
    schedule_flush()
    {:noreply, %{state | flush_count: state.flush_count + flushed}}
  end

  # ── Private ─────────────────────────────────────────────────────

  defp init_table do
    try do
      :ets.new(@buffer_table, [:named_table, :public, :ordered_set])
    rescue
      ArgumentError -> :ok
    end
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval_ms)
  end

  defp flush_buffer do
    entries = :ets.tab2list(@buffer_table)

    if entries == [] do
      0
    else
      Enum.each(entries, fn {id, attrs, _ts} ->
        try do
          case Observatory.Events.Event
               |> Ash.Changeset.for_create(:create, attrs)
               |> Ash.create() do
            {:ok, _event} ->
              :ets.delete(@buffer_table, id)
              maybe_upsert_session_async(attrs)

            {:error, changeset} ->
              Logger.warning("EventBuffer flush failed for #{id}: #{inspect(changeset.errors)}")
              :ets.delete(@buffer_table, id)
          end
        rescue
          e ->
            Logger.warning("EventBuffer flush error: #{inspect(e)}")
            :ets.delete(@buffer_table, id)
        catch
          :exit, _ ->
            :ets.delete(@buffer_table, id)
            :ok
        end
      end)

      length(entries)
    end
  end

  defp maybe_upsert_session_async(attrs) do
    hook_type = attrs[:hook_event_type] || attrs["hook_event_type"]

    case to_string(hook_type) do
      "SessionStart" ->
        payload = attrs[:payload] || attrs["payload"] || %{}

        try do
          Observatory.Events.Session
          |> Ash.Changeset.for_create(:create, %{
            session_id: attrs[:session_id] || attrs["session_id"],
            source_app: attrs[:source_app] || attrs["source_app"],
            agent_type: payload["agent_type"],
            model: payload["model"],
            started_at: DateTime.utc_now()
          })
          |> Ash.create()
        rescue
          _ -> :ok
        catch
          :exit, _ -> :ok
        end

      "SessionEnd" ->
        sid = attrs[:session_id] || attrs["session_id"]
        app = attrs[:source_app] || attrs["source_app"]

        try do
          require Ash.Query

          Observatory.Events.Session
          |> Ash.Query.filter(session_id == ^sid and source_app == ^app)
          |> Ash.read_one()
          |> case do
            {:ok, nil} -> :ok
            {:ok, session} -> session |> Ash.Changeset.for_update(:mark_ended) |> Ash.update()
            _ -> :ok
          end
        rescue
          _ -> :ok
        catch
          :exit, _ -> :ok
        end

      _ ->
        :ok
    end
  end

  defp build_event(attrs) do
    now = DateTime.utc_now()

    hook_type =
      case attrs[:hook_event_type] || attrs["hook_event_type"] do
        t when is_atom(t) -> t
        t when is_binary(t) -> String.to_existing_atom(t)
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
      inserted_at: now,
      updated_at: now
    }
  end
end
