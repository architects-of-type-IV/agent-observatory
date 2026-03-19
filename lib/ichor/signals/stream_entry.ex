defmodule Ichor.Signals.StreamEntry do
  @moduledoc """
  Structured signal stream entry. Common type for Buffer, PubSub broadcast, and LiveView rendering.
  Every signal that flows through the nervous system gets normalized into this shape.
  """

  @enforce_keys [:seq, :captured_at, :name, :category, :topic, :kind, :payload, :summary]
  defstruct [
    :seq,
    :captured_at,
    :name,
    :category,
    :topic,
    :kind,
    :payload,
    summary: %{text: "", fields: []}
  ]

  @type field :: %{key: atom(), value: term(), display: String.t()}

  @type t :: %__MODULE__{
          seq: non_neg_integer(),
          captured_at: DateTime.t(),
          name: atom(),
          category: atom(),
          topic: String.t(),
          kind: atom(),
          payload: map(),
          summary: %{text: String.t(), fields: [field()]}
        }
end
