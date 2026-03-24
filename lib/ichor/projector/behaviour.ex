defmodule Ichor.Projector.Behaviour do
  @moduledoc """
  Behaviour contract for signal projector modules.

  Every projector implements six callbacks:
  - `topics/0` - which event topics this projector watches
  - `init_state/1` - initial accumulator state for a given key
  - `handle_event/2` - accumulate an event into state
  - `ready?/2` - decide whether to flush (on :event or :timer trigger)
  - `build_signal/1` - construct the signal from accumulated state
  - `reset/1` - clear state after flush
  """

  alias Ichor.Events.Event
  alias Ichor.Projector.Signal

  @callback topics() :: [String.t()]
  @callback init_state(key :: term()) :: map()
  @callback handle_event(state :: map(), event :: Event.t()) :: map()
  @callback ready?(state :: map(), trigger :: :event | :timer) :: boolean()
  @callback build_signal(state :: map()) :: Signal.t() | nil
  @callback reset(state :: map()) :: map()
end
