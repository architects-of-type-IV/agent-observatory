defmodule Ichor.Signals.SignalProcess do
  @moduledoc """
  Generic per-key signal process that delegates policy to a signal module.

  One per {signal_module, key}. Accumulates events, checks readiness,
  dispatches to SignalHandler async on flush.

  Started dynamically by the Router via DynamicSupervisor + Registry.
  Replays stored events from last checkpoint on startup (ADR-026).
  """

  use GenServer, restart: :transient

  require Logger

  alias Ichor.Events.Event
  alias Ichor.Events.StoredEvent
  alias Ichor.Signals.Checkpoint

  @flush_interval 10_000
  @idle_timeout_ms 300_000

  def start_link(opts) do
    signal_module = Keyword.fetch!(opts, :signal)
    key = Keyword.fetch!(opts, :key)
    GenServer.start_link(__MODULE__, opts, name: via(signal_module, key))
  end

  def child_spec(opts) do
    signal_module = Keyword.fetch!(opts, :signal)
    key = Keyword.fetch!(opts, :key)

    %{
      id: {__MODULE__, signal_module, key},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  @spec push_event(module(), term(), Event.t()) :: :ok
  def push_event(module, key, %Event{} = event) do
    pid =
      case Registry.lookup(Ichor.Signals.ProcessRegistry, {module, key}) do
        [{pid, _}] ->
          pid

        [] ->
          case DynamicSupervisor.start_child(
                 Ichor.Signals.ProcessSupervisor,
                 {__MODULE__, signal: module, key: key}
               ) do
            {:ok, pid} -> pid
            {:error, {:already_started, pid}} -> pid
          end
      end

    GenServer.cast(pid, {:event, event})
  end

  defp via(signal_module, key) do
    {:via, Registry, {Ichor.Signals.ProcessRegistry, {signal_module, key}}}
  end

  @impl true
  def init(opts) do
    signal_module = Keyword.fetch!(opts, :signal)
    key = Keyword.fetch!(opts, :key)
    data = signal_module.init(key)
    data = maybe_replay(signal_module, key, data)

    state = %{
      signal_module: signal_module,
      key: key,
      data: data,
      timer_ref: nil,
      last_event_at: nil
    }

    {:ok, schedule_flush(state)}
  end

  @impl true
  def handle_cast({:event, %Event{} = event}, state) do
    state =
      state
      |> apply_event(event)
      |> Map.put(:last_event_at, System.monotonic_time(:millisecond))
      |> maybe_emit(:event)

    {:noreply, state}
  end

  @impl true
  def handle_info(:flush, state) do
    now = System.monotonic_time(:millisecond)
    idle_ms = if state.last_event_at, do: now - state.last_event_at, else: 0

    if idle_ms >= @idle_timeout_ms do
      Logger.debug(
        "[SignalProcess] Idle shutdown #{inspect(state.signal_module)}:#{inspect(state.key)}"
      )

      {:stop, :normal, state}
    else
      state =
        state
        |> clear_timer()
        |> maybe_emit(:timer)
        |> schedule_flush()

      {:noreply, state}
    end
  end

  def handle_info(msg, %{signal_module: m, data: d} = state) do
    {:noreply, %{state | data: m.handle_info(d, msg)}}
  end

  defp apply_event(%{signal_module: m, data: d} = state, event) do
    %{state | data: m.handle_event(event, d)}
  end

  defp maybe_emit(%{signal_module: m, data: d} = state, reason) do
    if m.ready?(d, reason), do: emit_signal(state), else: state
  end

  defp emit_signal(%{signal_module: m, data: d} = state) do
    case m.build_signal(d) do
      nil ->
        state

      signal ->
        Task.Supervisor.start_child(Ichor.TaskSupervisor, fn ->
          Ichor.Signals.SignalHandler.handle(signal)
        end)

        Phoenix.PubSub.broadcast(
          Ichor.PubSub,
          "signal:#{signal.name}",
          {:signal_activated, signal}
        )

        persist_checkpoint(state)
        %{state | data: m.reset(d)}
    end
  end

  defp schedule_flush(state) do
    ref = Process.send_after(self(), :flush, @flush_interval)
    %{state | timer_ref: ref}
  end

  defp clear_timer(%{timer_ref: nil} = state), do: state

  defp clear_timer(%{timer_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | timer_ref: nil}
  end

  defp maybe_replay(module, key, data) do
    module_name = to_string(module)
    key_str = to_string(key)

    case Checkpoint.for_resume(module_name, key_str) do
      {:ok, [%Checkpoint{} = checkpoint | _]} ->
        replay_from(module, checkpoint.last_event_occurred_at, data)

      _ ->
        data
    end
  rescue
    err ->
      Logger.warning("[SignalProcess] Replay error for #{inspect(module)}: #{inspect(err)}")
      data
  end

  defp replay_from(module, since, data) do
    # Collect all topics this module accepts by checking stored events
    case StoredEvent.since(since) do
      {:ok, events} ->
        events
        |> Enum.map(&stored_to_event/1)
        |> Enum.filter(&module.accepts?/1)
        |> Enum.reduce(data, fn event, acc -> module.handle_event(event, acc) end)

      {:error, reason} ->
        Logger.warning("[SignalProcess] Replay failed: #{inspect(reason)}")
        data
    end
  end

  defp stored_to_event(%StoredEvent{} = stored) do
    %Event{
      id: stored.id,
      topic: stored.topic,
      key: stored.key,
      occurred_at: stored.occurred_at,
      causation_id: stored.causation_id,
      correlation_id: stored.correlation_id,
      data: stored.data,
      metadata: stored.metadata
    }
  end

  defp persist_checkpoint(state) do
    module_name = to_string(state.signal_module)
    key_str = to_string(state.key)
    now = DateTime.utc_now()

    Task.Supervisor.start_child(Ichor.TaskSupervisor, fn ->
      Checkpoint.create(%{
        signal_module: module_name,
        key: key_str,
        last_event_occurred_at: now
      })
    end)
  end
end
