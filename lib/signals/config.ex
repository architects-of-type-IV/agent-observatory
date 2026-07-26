defmodule Signals.Config do
  @moduledoc """
  Runtime configuration.

      config :signals,
        signals: [MyApp.Signals.LoopDetected, MyApp.Signals.Watchdog],
        store: Signals.Store.ETS,
        sink: Signals.Sink.Local,
        default_source: "backend",
        emission_prefix: "signal.",
        default_interval_ms: nil,
        max_emission_depth: 4,
        dedup_window: 256

  ## `:dedup_window`

  How many recent event identities each accumulator remembers, to recognise a
  redelivery. Bounded because an accumulator reasons over a window anyway — a
  duplicate arriving long after that window has nothing left to corrupt — and
  because unbounded it would leak on a process meant to run for the life of the
  fleet.

  ## `:signals`

  The registered signal modules. This is the list the router consults; a signal
  not in it never sees an event, however well written.

  ## `:max_emission_depth`

  Signals may consume other signals' emissions, so an emission can trigger an
  emission. Depth is tracked per causal chain and cut off here — a pair of
  meta-signals watching each other would otherwise loop forever, and the loop
  looks like healthy throughput from outside.
  """

  @defaults %{
    signals: [],
    store: Signals.Store.ETS,
    sink: Signals.Sink.Local,
    registry: Signals.Registry,
    default_source: "backend",
    emission_prefix: "signal.",
    default_interval_ms: nil,
    max_emission_depth: 4,
    dedup_window: 256,
    partitions: 32
  }

  for {key, _} <- @defaults do
    @doc "The `#{key}` setting."
    @spec unquote(key)() :: term()
    def unquote(key)(), do: get(unquote(key))
  end

  @doc "Every setting as a map."
  @spec all() :: map()
  def all, do: Map.new(@defaults, fn {key, _} -> {key, get(key)} end)

  defp get(key), do: Application.get_env(:signals, key, Map.fetch!(@defaults, key))
end
