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
  @timer_interval_ms 10_000

  defstruct [:module, :key, :state, :handler]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    module = Keyword.fetch!(opts, :module)
    key = Keyword.fetch!(opts, :key)
    name = {:via, Registry, {Ichor.Signals.ProcessRegistry, {module, key}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec push_event(module(), term(), Event.t()) :: :ok
  def push_event(module, key, %Event{} = event) do
    case Registry.lookup(Ichor.Signals.ProcessRegistry, {module, key}) do
      [{pid, _}] ->
        GenServer.cast(pid, {:event, event})

      [] ->
        {:ok, pid} =
          DynamicSupervisor.start_child(
            Ichor.Signals.ProcessSupervisor,
            {__MODULE__, module: module, key: key}
          )

        GenServer.cast(pid, {:event, event})
    end

    :ok
  end

  @impl true
  def init(opts) do
    module = Keyword.fetch!(opts, :module)
    key = Keyword.fetch!(opts, :key)
    handler = Keyword.get(opts, :handler, Ichor.Signals.DefaultHandler)
    :timer.send_interval(@timer_interval_ms, :timer_tick)
    signal_state = module.init_state(key)

    {:ok,
     %__MODULE__{module: module, key: key, state: signal_state, handler: handler},
     @idle_timeout_ms}
  end

  @impl true
  def handle_cast({:event, %Event{} = event}, %__MODULE__{} = s) do
    new_signal_state = s.module.handle_event(s.state, event)
    s = %{s | state: new_signal_state}

    if s.module.ready?(new_signal_state, :event) do
      {:noreply, flush(s), @idle_timeout_ms}
    else
      {:noreply, s, @idle_timeout_ms}
    end
  end

  @impl true
  def handle_info(:timer_tick, %__MODULE__{} = s) do
    if s.module.ready?(s.state, :timer) do
      {:noreply, flush(s), @idle_timeout_ms}
    else
      {:noreply, s, @idle_timeout_ms}
    end
  end

  @impl true
  def handle_info(:timeout, s) do
    Logger.debug("[SignalProcess] Idle timeout for #{inspect(s.module)}:#{inspect(s.key)}")
    {:stop, :normal, s}
  end

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
