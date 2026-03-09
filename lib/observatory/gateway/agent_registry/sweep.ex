defmodule Observatory.Gateway.AgentRegistry.Sweep do
  @moduledoc """
  Garbage collection for stale agent entries.

  Full sweep: terminates BEAM process (cascades to tmux kill,
  AgentRegistry removal, EventBuffer cleanup via AgentProcess.terminate/2),
  then deletes the ETS entry.
  """

  alias Observatory.Gateway.AgentRegistry.AgentEntry
  alias Observatory.Fleet.{AgentProcess, FleetSupervisor}

  @table :gateway_agent_registry

  @doc "Remove stale agents and terminate their BEAM processes + tmux sessions."
  @spec run(non_neg_integer(), non_neg_integer()) :: :ok
  def run(ended_ttl_seconds, stale_ttl_seconds) do
    now = DateTime.utc_now()
    ended_cutoff = DateTime.add(now, -ended_ttl_seconds, :second)
    stale_cutoff = DateTime.add(now, -stale_ttl_seconds, :second)
    live_teams = live_team_names()

    @table
    |> :ets.tab2list()
    |> Enum.each(&maybe_sweep(&1, live_teams, ended_cutoff, stale_cutoff))

    sweep_orphan_processes()
  rescue
    ArgumentError -> :ok
  end

  # ── Sweep Rules (pattern-matched, declarative) ───────────────────

  defp maybe_sweep({_sid, %{id: "operator"}}, _live, _ended, _stale), do: :ok

  defp maybe_sweep({sid, %{team: team}}, live, _ended, _stale)
       when team != nil and live != nil do
    sweep_unless_member(sid, team, live)
  end

  defp maybe_sweep({sid, %{status: :ended, last_event_at: ts}}, _live, ended_cutoff, _stale) do
    sweep_if_before(sid, ts, ended_cutoff)
  end

  defp maybe_sweep({sid, %{role: :standalone, team: nil}}, _live, _ended, stale_cutoff) do
    sweep_standalone(sid, stale_cutoff)
  end

  defp maybe_sweep(_entry, _live, _ended, _stale), do: :ok

  # ── Standalone classification ────────────────────────────────────

  defp sweep_standalone(sid, _stale_cutoff) when not is_binary(sid), do: :ok

  defp sweep_standalone(sid, stale_cutoff) do
    case {Observatory.Gateway.TmuxDiscovery.infrastructure_session?(sid), AgentEntry.uuid?(sid)} do
      {true, _} -> full_sweep(sid)
      {_, false} -> full_sweep(sid)
      {_, true} -> sweep_stale_uuid(sid, stale_cutoff)
    end
  end

  defp sweep_stale_uuid(sid, stale_cutoff) do
    case :ets.lookup(@table, sid) do
      [{_, %{last_event_at: ts}}] -> sweep_if_before(sid, ts, stale_cutoff)
      _ -> :ok
    end
  end

  # ── DateTime-aware sweep predicates ──────────────────────────────

  defp sweep_if_before(_sid, nil, _cutoff), do: :ok

  defp sweep_if_before(sid, ts, cutoff) do
    case DateTime.compare(ts, cutoff) do
      :lt -> full_sweep(sid)
      _ -> :ok
    end
  end

  defp sweep_unless_member(sid, team, live) do
    case MapSet.member?(live, team) do
      true -> :ok
      false -> full_sweep(sid)
    end
  end

  # ── Full Sweep ───────────────────────────────────────────────────

  defp full_sweep(session_id) do
    terminate_process(session_id)
    Observatory.EventBuffer.remove_session(session_id)
    :ets.delete(@table, session_id)
  rescue
    ArgumentError -> :ok
  end

  # ── Orphan Process Sweep ─────────────────────────────────────────

  defp sweep_orphan_processes do
    known_ids =
      @table
      |> :ets.tab2list()
      |> Enum.map(fn {sid, _} -> sid end)
      |> MapSet.new()
      |> MapSet.union(event_session_ids())

    AgentProcess.list_all()
    |> Enum.reject(fn {id, _} -> id == "operator" or MapSet.member?(known_ids, id) end)
    |> Enum.each(fn {id, _} -> terminate_process(id) end)
  rescue
    _ -> :ok
  end

  defp event_session_ids do
    Observatory.EventBuffer.list_events()
    |> Enum.map(& &1.session_id)
    |> MapSet.new()
  end

  # ── Process Termination ──────────────────────────────────────────

  defp terminate_process(session_id) do
    with {pid, _meta} <- AgentProcess.lookup(session_id),
         {:error, :not_found} <- FleetSupervisor.terminate_agent(session_id) do
      GenServer.stop(pid, :normal)
    end
  catch
    :exit, _ -> :ok
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp live_team_names do
    Observatory.Fleet.TeamSupervisor.list_all()
    |> Enum.map(fn {name, _meta} -> name end)
    |> MapSet.new()
  rescue
    _ -> nil
  end
end
