defmodule Ichor.Fleet.Queries do
  @moduledoc """
  Compatibility wrapper for fleet view/query derivation.
  """
  defdelegate active_sessions(events, opts \\ []), to: Ichor.Fleet.Analysis.Queries
  defdelegate inspector_events(teams, events), to: Ichor.Fleet.Analysis.Queries
  defdelegate topology(all_sessions, teams, now), to: Ichor.Fleet.Analysis.Queries
end
