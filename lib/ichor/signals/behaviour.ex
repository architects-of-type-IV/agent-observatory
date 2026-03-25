defmodule Ichor.Signals.Behaviour do
  @moduledoc """
  Contract for Signal modules. Each Signal is a stateful accumulator that
  watches event topics, accumulates events, and flushes when ready.
  """

  alias Ichor.Events.Event
  alias Ichor.Signals.Signal

  @callback topics() :: [String.t()]
  @callback init_state(key :: term()) :: map()
  @callback handle_event(state :: map(), event :: Event.t()) :: map()
  @callback ready?(state :: map(), trigger :: :event | :timer) :: boolean()
  @callback build_signal(state :: map()) :: Signal.t() | nil
  @callback reset(state :: map()) :: map()
end
