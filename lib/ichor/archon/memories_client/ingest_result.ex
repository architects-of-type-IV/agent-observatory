defmodule Ichor.Archon.MemoriesClient.IngestResult do
  @moduledoc "Response from a single-episode ingest."

  @type t :: %__MODULE__{
          episode_id: String.t(),
          group_id: String.t(),
          status: String.t(),
          sync_status: String.t()
        }

  @enforce_keys [:episode_id, :group_id, :status, :sync_status]
  defstruct [:episode_id, :group_id, :status, :sync_status]
end
