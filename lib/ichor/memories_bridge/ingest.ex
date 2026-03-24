defmodule Ichor.MemoriesBridge.Ingest do
  @moduledoc """
  Payload struct matching the Memories `/api/episodes/ingest` contract.
  """

  @type episode_type :: :text | :message | :json
  @type source :: :user | :agent | :system | :document | :api

  @type t :: %__MODULE__{
          content: String.t(),
          type: episode_type(),
          source: source(),
          space: String.t(),
          extraction_instructions: String.t() | nil,
          reference_timestamp: DateTime.t() | nil,
          name: String.t() | nil,
          source_description: String.t() | nil,
          user_id: String.t() | nil
        }

  @enforce_keys [:content, :space]
  defstruct [
    :content,
    :space,
    :extraction_instructions,
    :reference_timestamp,
    :name,
    :source_description,
    :user_id,
    type: :text,
    source: :system
  ]
end
