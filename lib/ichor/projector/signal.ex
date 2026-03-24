defmodule Ichor.Projector.Signal do
  @moduledoc """
  Signal envelope. Emitted when a projector decides "enough happened."

  A Signal carries the accumulated events that triggered it, a name describing
  what was decided, and metadata about the decision.
  """

  @enforce_keys [:name, :key, :events, :emitted_at]
  defstruct [:name, :key, :events, :metadata, :emitted_at]

  @type t :: %__MODULE__{
          name: String.t(),
          key: term(),
          events: [Ichor.Events.Event.t()],
          metadata: map() | nil,
          emitted_at: DateTime.t()
        }

  @spec new(String.t(), term(), [Ichor.Events.Event.t()], map()) :: t()
  def new(name, key, events, metadata \\ %{}) do
    %__MODULE__{
      name: name,
      key: key,
      events: events,
      metadata: metadata,
      emitted_at: DateTime.utc_now()
    }
  end
end
