defmodule Ichor.Signals.SignalProcess do
  @moduledoc """
  Stateful accumulator GenServer. One per {signal_module, key}.
  Accumulates events, checks ready?, calls handler on flush.

  Started dynamically by the Router via DynamicSupervisor + Registry.
  Shuts down after idle timeout.
  """

  use GenServer, restart: :transient

  require Logger

  alias Ichor.Events.Event

  @idle_timeout_ms 300_000
  @flush_interval_ms 10_000

  defstruct [:module, :key, :state, :handler, last_event_at: nil]

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
    handler = Keyword.get(opts, :handler, Ichor.Signals.DefaultHandler)
    signal_state = module.init_state(key)
    schedule_tick()

    {:ok, %__MODULE__{module: module, key: key, state: signal_state, handler: handler}}
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
    if function_exported?(s.module, :handle_info, 2) do
      {:noreply, %{s | state: s.module.handle_info(s.state, msg)}}
    else
      {:noreply, s}
    end
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @flush_interval_ms)

  defp flush(%__MODULE__{} = s) do
    case s.module.build_signal(s.state) do
      nil ->
        s

      signal ->
        s.handler.handle(signal)

        Phoenix.PubSub.broadcast(
          Ichor.PubSub,
          "signal:#{signal.name}",
          {:signal_activated, signal}
        )

        %{s | state: s.module.reset(s.state)}
    end
  end
end
