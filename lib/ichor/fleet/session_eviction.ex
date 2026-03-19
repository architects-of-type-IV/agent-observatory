defmodule Ichor.Fleet.SessionEviction do
  @moduledoc """
  Compatibility wrapper for fleet session eviction.
  """
  defdelegate evict_stale(events, now), to: Ichor.Fleet.Analysis.SessionEviction
end
