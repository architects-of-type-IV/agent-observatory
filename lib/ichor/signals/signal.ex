defmodule Ichor.Signals.Signal do
  @moduledoc """
  Emitted when a Signal process decides "enough happened."
  Contains the accumulated events that triggered it.
  """

  @enforce_keys [:name, :key, :events, :emitted_at]
  defstruct [
    :name,
    :key,
    :events,
    :emitted_at,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          key: term(),
          events: [Ichor.Events.Event.t()],
          emitted_at: DateTime.t(),
          metadata: map()
        }

  @spec new(String.t(), term(), [Ichor.Events.Event.t()], map()) :: t()
  def new(name, key, events, metadata \\ %{}) do
    %__MODULE__{
      name: name,
      key: key,
      events: events,
      emitted_at: DateTime.utc_now(),
      metadata: metadata
    }
  end
end
