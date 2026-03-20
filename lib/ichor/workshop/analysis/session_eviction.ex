defmodule Ichor.Workshop.Analysis.SessionEviction do
  @moduledoc """
  Evicts events from stale sessions that have not produced
  new activity within the TTL window. Agent-agnostic: works
  for any event source.
  """

  @session_ttl_seconds 600

  @doc """
  Purge events from sessions whose latest event is older than the TTL.
  Returns the list unchanged when no eviction is possible.
  Events are expected newest-first (prepend-ordered).
  """
  @spec evict_stale(list(), DateTime.t()) :: list()
  def evict_stale([], _now), do: []

  def evict_stale(events, now) do
    oldest = List.last(events)

    case DateTime.diff(now, oldest.inserted_at) > @session_ttl_seconds do
      false -> events
      true -> do_evict(events, now)
    end
  end

  defp do_evict(events, now) do
    stale_sids = stale_session_ids(events, now)
    reject_stale(events, stale_sids)
  end

  defp stale_session_ids(events, now) do
    for {sid, evts} <- Enum.group_by(events, & &1.session_id),
        latest = Enum.max_by(evts, & &1.inserted_at, DateTime),
        DateTime.diff(now, latest.inserted_at) > @session_ttl_seconds,
        into: MapSet.new(),
        do: sid
  end

  defp reject_stale(events, stale_sids) when stale_sids == %MapSet{},
    do: events

  defp reject_stale(events, stale_sids),
    do: Enum.reject(events, &MapSet.member?(stale_sids, &1.session_id))
end
