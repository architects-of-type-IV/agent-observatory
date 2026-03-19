defmodule Ichor.Archon.MemoriesClient.ChunkedIngestResult do
  @moduledoc "Response from a chunked-episode ingest (content >4KB)."

  alias Ichor.Archon.MemoriesClient.IngestResult

  @type t :: %__MODULE__{
          chunked: boolean(),
          chunk_count: non_neg_integer(),
          episodes: [IngestResult.t()]
        }

  @enforce_keys [:chunked, :chunk_count, :episodes]
  defstruct [:chunked, :chunk_count, :episodes]
end
