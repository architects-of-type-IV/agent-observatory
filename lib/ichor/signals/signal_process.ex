defmodule Ichor.Signals.SignalProcess do
  @moduledoc """
  Stateful accumulator GenServer. One per {signal_module, key}.
  Accumulates events, checks ready?, calls handler on flush.

  Started dynamically by the Router via DynamicSupervisor + Registry.
  Shuts down after idle timeout.

  On startup, replays stored events from the last checkpoint position to rebuild
  accumulator state before accepting live events (ADR-026).
  """

  use GenServer, restart: :transient

  require Logger

  alias Ichor.Events.Event
  alias Ichor.Events.StoredEvent
  alias Ichor.Signals.Checkpoint

  @idle_timeout_ms 300_000
  @flush_interval_ms 10_000

  defstruct [:module, :key, :state, last_event_at: nil]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    module = Keyword.fetch!(opts, :module)
    key = Keyword.fetch!(opts, :key)
    name = {:via, Registry, {Ichor.Signals.ProcessRegistry, {module, key}}}
    GenServer.start_link(__MODULE__, opts, name: name)
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
                 {__MODULE__, module: module, key: key}
               ) do
            {:ok, pid} -> pid
            {:error, {:already_started, pid}} -> pid
          end
      end

    GenServer.cast(pid, {:event, event})
  end

  @impl true
  def init(opts) do
    module = Keyword.fetch!(opts, :module)
    key = Keyword.fetch!(opts, :key)
    signal_state = module.init_state(key)
    signal_state = maybe_replay(module, key, signal_state)
    schedule_tick()

    {:ok, %__MODULE__{module: module, key: key, state: signal_state}}
  end

  @impl true
  def handle_cast({:event, %Event{} = event}, %__MODULE__{} = s) do
    new_signal_state = s.module.handle_event(s.state, event)
    s = %{s | state: new_signal_state, last_event_at: System.monotonic_time(:millisecond)}

    if s.module.ready?(new_signal_state, :event) do
      {:noreply, flush(s)}
    else
      {:noreply, s}
    end
  end

  @impl true
  def handle_info(:tick, %__MODULE__{} = s) do
    now = System.monotonic_time(:millisecond)
    idle_ms = if s.last_event_at, do: now - s.last_event_at, else: 0

    cond do
      idle_ms >= @idle_timeout_ms ->
        Logger.debug("[SignalProcess] Idle shutdown #{inspect(s.module)}:#{inspect(s.key)}")
        {:stop, :normal, s}

      s.module.ready?(s.state, :timer) ->
        schedule_tick()
        {:noreply, flush(s)}

      true ->
        schedule_tick()
        {:noreply, s}
    end
  end

  @impl true
  def handle_info(msg, %__MODULE__{} = s) do
    {:noreply, %{s | state: s.module.handle_info(s.state, msg)}}
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @flush_interval_ms)

  defp maybe_replay(module, key, state) do
    module_name = to_string(module)
    key_str = to_string(key)

    case Checkpoint.for_resume(module_name, key_str) do
      {:ok, [%Checkpoint{} = checkpoint | _]} ->
        replay_from(module, checkpoint.last_event_occurred_at, state)

      _ ->
        state
    end
  rescue
    err ->
      Logger.warning("[SignalProcess] Replay error for #{inspect(module)}: #{inspect(err)}")
      state
  end

  defp replay_from(module, since, state) do
    topics = module.topics()

    case StoredEvent.for_replay(topics, since) do
      {:ok, events} ->
        Enum.reduce(events, state, fn stored, acc ->
          event = stored_to_event(stored)
          module.handle_event(acc, event)
        end)

      {:error, reason} ->
        Logger.warning("[SignalProcess] for_replay failed: #{inspect(reason)}")
        state
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

  defp flush(%__MODULE__{} = s) do
    case s.module.build_signal(s.state) do
      nil ->
        s

      signal ->
        module = s.module

        Task.Supervisor.start_child(Ichor.TaskSupervisor, fn ->
          module.handle(signal)
        end)

        Phoenix.PubSub.broadcast(
          Ichor.PubSub,
          "signal:#{signal.name}",
          {:signal_activated, signal}
        )

        persist_checkpoint(s)
        %{s | state: s.module.reset(s.state)}
    end
  end

  defp persist_checkpoint(%__MODULE__{} = s) do
    module_name = to_string(s.module)
    key_str = to_string(s.key)
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
