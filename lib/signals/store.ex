defmodule Signals.Store do
  @moduledoc """
  Behaviour for persisting accumulator state and log position.

  An accumulator holds a partial conclusion — three of the five crashes that
  make a cascade, forty of the fifty tool calls that exhaust a budget. Losing it
  on restart does not lose an event; it loses the *reasoning so far*, and the
  signal silently starts over. A watchdog that resets its clock every deploy
  never fires.

  So state and position are stored together, and both are restored on start.
  The position is what makes replay safe: an accumulator that has already folded
  in event 41 discards it if the log hands it back.

  Configure with:

      config :signals, store: MyApp.SignalStore
  """

  @typedoc "Signal name and partition key — the identity of one accumulator."
  @type ref :: {name :: String.t(), key :: String.t() | nil}

  @doc "Persist state and the last folded position for one accumulator."
  @callback put(ref(), state :: term(), position :: integer() | nil) :: :ok | {:error, term()}

  @doc """
  Load state and position.

  `{:ok, :empty}` for an accumulator that has never run — the caller then asks
  the signal for a fresh `init/1` rather than guessing a shape.
  """
  @callback fetch(ref()) ::
              {:ok, %{state: term(), position: integer() | nil}}
              | {:ok, :empty}
              | {:error, term()}

  @doc "Forget an accumulator entirely."
  @callback delete(ref()) :: :ok | {:error, term()}
end

defmodule Signals.Sink do
  @moduledoc """
  Behaviour for what happens to an emission.

  A signal's conclusion has two audiences that must not be conflated:

    * **other signals**, which consume it as input — this is what makes
      meta-signals possible, and it requires the emission to re-enter routing
    * **the world** — PubSub, a durable log, an Oban job, a dashboard

  `publish/1` covers both: it hands the emission back for routing *and* onward.
  An implementation that only broadcasts and never re-routes quietly disables
  every meta-signal, with no error anywhere.

  Configure with:

      config :signals, sink: MyApp.SignalSink
  """

  alias Signals.Event

  @doc "Handle an emitted signal event."
  @callback publish(Event.t()) :: :ok | {:error, term()}
end
