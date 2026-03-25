defmodule Ichor.Signals.Behaviour do
  @moduledoc """
  Contract for Signal modules.

  A signal is a stateful accumulator that watches domain events,
  accumulates them, and emits a signal when a readiness condition is met.
  The handler (what to DO with the signal) is separate.
  """

  alias Ichor.Events.Event
  alias Ichor.Signals.Signal

  @callback name() :: atom()
  @callback accepts?(event :: Event.t()) :: boolean()
  @callback init(key :: term()) :: map()
  @callback handle_event(event :: Event.t(), state :: map()) :: map()
  @callback ready?(state :: map(), reason :: :event | :timer) :: boolean()
  @callback build_signal(state :: map()) :: Signal.t() | nil
  @callback reset(state :: map()) :: map()
end
