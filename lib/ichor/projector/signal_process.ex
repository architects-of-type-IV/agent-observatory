defmodule Ichor.Projector.SignalProcess do
  @moduledoc """
  Per-key signal process. One instance per `{signal_module, key}`.

  Accumulates events via the signal module's `handle_event/2` callback,
  checks `ready?/2` after each event and on a periodic timer, and calls
  `build_signal/1` + handler on flush.
  """

  use GenServer

  @flush_interval :timer.seconds(30)

  @spec route(module(), Ichor.Events.Event.t()) :: :ok
  def route(signal_module, event) do
    name = via(signal_module, event.key)

    case GenServer.whereis(name) do
      nil ->
        DynamicSupervisor.start_child(
          Ichor.Projector.Supervisor,
          {__MODULE__, {signal_module, event.key}}
        )

        GenServer.cast(name, {:event, event})

      _pid ->
        GenServer.cast(name, {:event, event})
    end

    :ok
  end

  @spec start_link({module(), term()}) :: GenServer.on_start()
  def start_link({signal_module, key}) do
    GenServer.start_link(__MODULE__, {signal_module, key}, name: via(signal_module, key))
  end

  defp via(signal_module, key) do
    {:via, Registry, {Ichor.Projector.Registry, {signal_module, key}}}
  end

  @impl true
  def init({signal_module, key}) do
    state = %{
      module: signal_module,
      key: key,
      inner: signal_module.init_state(key),
      timer: schedule_flush()
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:event, event}, state) do
    inner = state.module.handle_event(state.inner, event)
    state = %{state | inner: inner}

    if state.module.ready?(inner, :event) do
      flush_and_reset(state)
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:flush, state) do
    if state.module.ready?(state.inner, :timer) do
      flush_and_reset(state)
    else
      {:noreply, %{state | timer: schedule_flush()}}
    end
  end

  defp flush_and_reset(state) do
    case state.module.build_signal(state.inner) do
      nil ->
        {:noreply, %{state | inner: state.module.reset(state.inner), timer: schedule_flush()}}

      signal ->
        Ichor.Projector.SignalHandler.handle(signal)
        {:noreply, %{state | inner: state.module.reset(state.inner), timer: schedule_flush()}}
    end
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval)
  end
end
