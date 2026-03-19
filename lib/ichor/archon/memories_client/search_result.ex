defmodule Ichor.Archon.MemoriesClient.SearchResult do
  @moduledoc "A single edge/node result from a graph search."

  @type t :: %__MODULE__{
          uuid: String.t() | nil,
          fact: String.t() | nil,
          name: String.t() | nil,
          source: String.t() | nil,
          target: String.t() | nil,
          score: float() | nil,
          created_at: String.t() | nil
        }

  defstruct [:uuid, :fact, :name, :source, :target, :score, :created_at]
end
