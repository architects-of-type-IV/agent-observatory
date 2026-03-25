defmodule Ichor.Events.Event do
  @moduledoc """
  Single event envelope for all domain facts in the ICHOR event system.

  Events use dot-delimited topic strings (not atoms):
  - "chat.message.created" -- good: domain fact
  - "agent.session.started" -- good: domain fact
  - "new_event" -- bad: framework noise
  """

  @enforce_keys [:id, :topic, :key, :occurred_at, :data]
  defstruct [
    :id,
    :topic,
    :key,
    :occurred_at,
    :causation_id,
    :correlation_id,
    :data,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          topic: String.t(),
          key: term(),
          occurred_at: DateTime.t(),
          causation_id: String.t() | nil,
          correlation_id: String.t() | nil,
          data: map(),
          metadata: map()
        }

  @spec new(String.t(), term(), map(), map()) :: t()
  def new(topic, key, data, metadata \\ %{}) when is_binary(topic) do
    %__MODULE__{
      id: Ash.UUID.generate(),
      topic: topic,
      key: key,
      occurred_at: DateTime.utc_now(),
      data: data,
      metadata: metadata
    }
  end
end
