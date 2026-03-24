defmodule Ichor.Events.Event do
  @moduledoc """
  Normalized event envelope. One shape for every domain event in the system.

  Events are domain facts, not framework noise:
  - "agent.session.started" not "session_started"
  - "chat.message.created" not "new_event"
  - "pipeline.task.completed" not "pipeline_task_completed"
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
    :metadata
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          topic: String.t(),
          key: term(),
          occurred_at: DateTime.t(),
          causation_id: String.t() | nil,
          correlation_id: String.t() | nil,
          data: map(),
          metadata: map() | nil
        }

  @spec new(String.t(), term(), map(), map()) :: t()
  def new(topic, key, data, metadata \\ %{}) do
    %__MODULE__{
      id: Ash.UUID.generate(),
      topic: topic,
      key: key,
      occurred_at: DateTime.utc_now(),
      causation_id: nil,
      correlation_id: nil,
      data: data,
      metadata: metadata
    }
  end
end
