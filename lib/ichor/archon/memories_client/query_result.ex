defmodule Ichor.Archon.MemoriesClient.QueryResult do
  @moduledoc "Response from a memory query (retrieval-augmented answer)."

  @type t :: %__MODULE__{
          answer: String.t() | nil,
          citations: [map()] | nil,
          context: map() | nil
        }

  defstruct [:answer, :citations, :context]
end
