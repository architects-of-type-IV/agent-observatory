defmodule Observatory.Gateway.AgentRegistry.Sweep do
  @moduledoc """
  Garbage collection for stale agent entries in the ETS registry.

  Sweeps ended agents past their TTL, agents from deleted teams,
  infrastructure sessions, and idle standalone agents.
  """

  alias Observatory.Gateway.AgentRegistry.AgentEntry

  @table :gateway_agent_registry

  @doc "Remove stale and ended agents from the ETS table."
  @spec run(non_neg_integer(), non_neg_integer()) :: :ok
  def run(ended_ttl_seconds, stale_ttl_seconds) do
    now = DateTime.utc_now()
    ended_cutoff = DateTime.add(now, -ended_ttl_seconds, :second)
    stale_cutoff = DateTime.add(now, -stale_ttl_seconds, :second)
    live_teams = live_team_names()

    :ets.tab2list(@table)
    |> Enum.each(fn {session_id, agent} ->
      maybe_sweep(session_id, agent, live_teams, ended_cutoff, stale_cutoff)
    end)
  rescue
    ArgumentError -> :ok
  end

  # Never sweep the operator
  defp maybe_sweep(_sid, %{id: "operator"}, _live, _ended, _stale), do: :ok

  # Sweep agents from deleted teams
  defp maybe_sweep(sid, %{team: team}, live, _ended, _stale)
       when team != nil and live != nil do
    case MapSet.member?(live, team) do
      true -> :ok
      false -> :ets.delete(@table, sid)
    end
  end

  # Sweep ended agents past TTL
  defp maybe_sweep(sid, %{status: :ended, last_event_at: ts}, _live, ended_cutoff, _stale) do
    case DateTime.compare(ts, ended_cutoff) do
      :lt -> :ets.delete(@table, sid)
      _ -> :ok
    end
  end

  # Sweep infrastructure sessions and non-UUID standalones; stale UUID standalones
  defp maybe_sweep(sid, %{role: :standalone, team: nil} = agent, _live, _ended, stale_cutoff) do
    case {Observatory.Gateway.TmuxDiscovery.infrastructure_session?(sid), AgentEntry.uuid?(sid)} do
      {true, _} -> :ets.delete(@table, sid)
      {_, false} -> :ets.delete(@table, sid)
      {_, true} -> sweep_if_stale(agent, sid, stale_cutoff)
    end
  end

  defp maybe_sweep(_sid, _agent, _live, _ended, _stale), do: :ok

  defp sweep_if_stale(%{last_event_at: ts}, sid, stale_cutoff) do
    case DateTime.compare(ts, stale_cutoff) do
      :lt -> :ets.delete(@table, sid)
      _ -> :ok
    end
  end

  defp live_team_names do
    Observatory.Fleet.TeamSupervisor.list_all()
    |> Enum.map(fn {name, _meta} -> name end)
    |> MapSet.new()
  rescue
    _ -> nil
  end
end
