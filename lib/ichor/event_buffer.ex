defmodule Ichor.EventBuffer do
  @moduledoc """
  Compatibility shim. Delegates all calls to `Ichor.Events.Runtime`.

  `Events.Runtime` is the canonical owner of the event buffer. This module
  exists solely to avoid breaking callers in control/ and projects/ that
  reference `Ichor.EventBuffer` directly.
  """

  alias Ichor.Events.Runtime

  @doc "Ingest a hook event map. Drops events for tombstoned sessions."
  @spec ingest(map()) :: {:ok, map()}
  defdelegate ingest(event_attrs), to: Runtime

  @doc "Get all events from the buffer (most recent first)."
  @spec list_events() :: [map()]
  defdelegate list_events(), to: Runtime

  @doc "Get the latest event per session (lightweight seed for dashboard mount)."
  @spec latest_per_session() :: [map()]
  defdelegate latest_per_session(), to: Runtime

  @doc "Returns a MapSet of all unique non-empty cwd values from the event buffer."
  @spec unique_project_cwds() :: MapSet.t(String.t())
  defdelegate unique_project_cwds(), to: Runtime

  @doc "Get events for a specific session."
  @spec events_for_session(String.t()) :: [map()]
  defdelegate events_for_session(session_id), to: Runtime

  @doc "Remove all events for a session and tombstone it."
  @spec remove_session(String.t()) :: :ok
  defdelegate remove_session(session_id), to: Runtime

  @doc "Place a 30s tombstone to reject late events without purging existing ones."
  @spec tombstone_session(String.t()) :: :ok
  defdelegate tombstone_session(session_id), to: Runtime
end
