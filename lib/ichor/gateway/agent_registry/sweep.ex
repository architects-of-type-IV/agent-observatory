defmodule Ichor.Gateway.AgentRegistry.Sweep do
  @moduledoc """
  Garbage collection for stale agent entries.

  Liveness is determined by observable facts (OS pid, tmux session),
  not by hook events. SessionEnd is a convenience hint, not required.

  Full sweep: terminates BEAM process (cascades to tmux kill,
  AgentRegistry removal, EventBuffer cleanup via AgentProcess.terminate/2),
  then deletes the ETS entry.
  """

  require Logger

  alias Ichor.Fleet.{AgentProcess, FleetSupervisor}
  alias Ichor.Fleet.TeamSupervisor
  alias Ichor.Gateway.AgentRegistry.AgentEntry
  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.Gateway.TmuxDiscovery

  @table :gateway_agent_registry

  @doc "Remove stale agents and terminate their BEAM processes + tmux sessions."
  @spec run(non_neg_integer(), non_neg_integer()) :: :ok
  def run(ended_ttl_seconds, stale_ttl_seconds) do
    now = DateTime.utc_now()
    ended_cutoff = DateTime.add(now, -ended_ttl_seconds, :second)
    stale_cutoff = DateTime.add(now, -stale_ttl_seconds, :second)
    live_teams = live_team_names()
    live_tmux = live_tmux_sessions()

    @table
    |> :ets.tab2list()
    |> Enum.each(&maybe_sweep(&1, live_teams, live_tmux, ended_cutoff, stale_cutoff))

    sweep_orphan_processes()
  rescue
    ArgumentError -> :ok
  end

  # ── Sweep Rules ───────────────────────────────────────────────────

  defp maybe_sweep({_sid, %{id: "operator"}}, _live, _tmux, _ended, _stale), do: :ok

  defp maybe_sweep({sid, entry}, live, live_tmux, ended_cutoff, stale_cutoff) do
    cond do
      # Observable liveness checks — no hook required
      dead_by_pid?(entry) ->
        Logger.info("[Sweep] #{sid} removed: os_pid #{entry[:os_pid]} is dead")
        full_sweep(sid)

      dead_by_tmux?(entry, live_tmux) ->
        Logger.info("[Sweep] #{sid} removed: tmux session #{entry[:tmux_session]} is gone")
        full_sweep(sid)

      # Hook-assisted hint: clean exit signalled via SessionEnd
      entry[:status] == :ended ->
        sweep_if_before(sid, entry[:last_event_at], ended_cutoff, "SessionEnd + TTL elapsed")

      # Team member whose team is gone
      entry[:team] != nil ->
        sweep_unless_member(sid, entry[:team], live)

      # Standalone agent past stale TTL
      entry[:role] == :standalone and entry[:team] == nil ->
        sweep_standalone(sid, stale_cutoff)

      true ->
        :ok
    end
  end

  # ── Liveness Checks ──────────────────────────────────────────────
  # Failure mode is always :keep — if we cannot confirm dead, do not sweep.

  defp dead_by_pid?(%{os_pid: pid}) when is_integer(pid) do
    not pid_alive?(pid)
  end

  defp dead_by_pid?(_), do: false

  # :error means tmux listing failed — treat as unknown, keep the agent.
  defp dead_by_tmux?(%{tmux_session: tmux}, {:ok, live_tmux})
       when is_binary(tmux) and tmux != "" do
    not MapSet.member?(live_tmux, tmux)
  end

  defp dead_by_tmux?(_entry, _live_tmux), do: false

  defp pid_alive?(os_pid) do
    match?({_, 0}, System.cmd("kill", ["-0", to_string(os_pid)], stderr_to_stdout: true))
  end

  # ── Standalone classification ────────────────────────────────────

  defp sweep_standalone(sid, _stale_cutoff) when not is_binary(sid), do: :ok

  defp sweep_standalone(sid, stale_cutoff) do
    case {TmuxDiscovery.infrastructure_session?(sid), AgentEntry.uuid?(sid)} do
      {true, _} ->
        Logger.info("[Sweep] #{sid} removed: infrastructure session")
        full_sweep(sid)

      {_, false} ->
        Logger.info("[Sweep] #{sid} removed: standalone non-UUID with no team")
        full_sweep(sid)

      {_, true} ->
        sweep_stale_uuid(sid, stale_cutoff)
    end
  end

  defp sweep_stale_uuid(sid, stale_cutoff) do
    case :ets.lookup(@table, sid) do
      [{_, %{last_event_at: ts}}] ->
        sweep_if_before(sid, ts, stale_cutoff, "stale idle TTL elapsed")

      _ ->
        :ok
    end
  end

  # ── DateTime-aware sweep predicates ──────────────────────────────

  defp sweep_if_before(_sid, nil, _cutoff, _reason), do: :ok

  defp sweep_if_before(sid, ts, cutoff, reason) do
    case DateTime.compare(ts, cutoff) do
      :lt ->
        Logger.info("[Sweep] #{sid} removed: #{reason} (last_event_at=#{ts})")
        full_sweep(sid)

      _ ->
        :ok
    end
  end

  defp sweep_unless_member(sid, team, live) do
    case MapSet.member?(live, team) do
      true ->
        :ok

      false ->
        Logger.info("[Sweep] #{sid} removed: team #{team} is no longer alive")
        full_sweep(sid)
    end
  end

  # ── Full Sweep ───────────────────────────────────────────────────

  defp full_sweep(session_id) do
    terminate_process(session_id)
    # EventBuffer cleanup cascades via AgentProcess.terminate/2
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
    :event_buffer_events
    |> :ets.tab2list()
    |> Enum.map(fn {_id, event} -> event.session_id end)
    |> MapSet.new()
  rescue
    ArgumentError -> MapSet.new()
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
    TeamSupervisor.list_all()
    |> Enum.map(fn {name, _meta} -> name end)
    |> MapSet.new()
  rescue
    _ -> nil
  end

  defp live_tmux_sessions do
    {:ok, Tmux.list_sessions() |> MapSet.new()}
  rescue
    _ -> :error
  end
end
