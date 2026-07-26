defmodule Signals.SignalCase do
  @moduledoc """
  Boots the runtime with a per-test signal roster.

  Set the signals under test with `@tag signals: [MySignal]`. Everything is
  restarted between tests so no accumulator leaks state across them.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Signals.SignalCase
      alias Signals.Event
    end
  end

  setup tags do
    put_config(:signals, tags[:signals] || [])
    put_config(:store, tags[:store] || Signals.Store.ETS)
    put_config(:sink, tags[:sink] || Signals.Sink.Local)
    if depth = tags[:max_emission_depth], do: put_config(:max_emission_depth, depth)

    start_supervised!(Signals.Store.ETS)
    start_supervised!(Signals.Sink.Local)
    start_supervised!(Signals.Registry)

    Signals.Store.ETS.clear()
    :ok = Signals.Sink.Collector.setup()

    on_exit(fn ->
      for key <- [:signals, :store, :sink, :max_emission_depth, :default_interval_ms] do
        Application.delete_env(:signals, key)
      end
    end)

    :ok
  end

  @doc "Set a `:signals` config key for this test."
  def put_config(key, value), do: Application.put_env(:signals, key, value)

  @doc "Emit an event and wait for accumulators to drain it."
  def emit(type, opts \\ []) do
    result = Signals.emit(type, opts)
    sync()
    result
  end

  @doc """
  Wait for every running accumulator to finish its mailbox.

  Dispatch is a cast, so without this a test asserts on state the accumulator
  has not folded yet.
  """
  def sync do
    for {_signal, _key, pid} <- Signals.accumulators() do
      :sys.get_state(pid)
    end

    # The sink re-routes on publish, so a second pass catches emissions that
    # arrived at a meta-signal during the first.
    for {_signal, _key, pid} <- Signals.accumulators() do
      :sys.get_state(pid)
    end

    :ok
  end

  @doc "Fire a signal's timer trigger directly, without waiting for the interval."
  def tick(signal, key \\ nil) do
    case Signals.Registry.whereis(signal, key) do
      nil -> :no_accumulator
      pid -> Signals.Accumulator.tick(pid) && :sys.get_state(pid) && :ok
    end
  end
end
