defmodule Ichor.Mes.Janitor do
  @moduledoc """
  Monitors RunProcess lifecycle and cleans up orphaned resources.

  OTP guarantee: `terminate/2` is NOT guaranteed to fire (brutal kills,
  supervisor max_restarts exceeded). This GenServer uses `Process.monitor/1`
  to detect RunProcess death regardless of cause and cleans up:

    1. Fleet TeamSupervisor (disbands the team, terminates AgentProcesses)
    2. Tmux session (kills the tmux session and windows)
    3. Prompt files on disk

  Also runs a periodic sweep every 2 minutes as a safety net for any
  resources that slip through (e.g., if Janitor itself restarts).
  """

  use GenServer

  alias Ichor.Fleet.FleetSupervisor
  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.Mes.{RunProcess, TeamLifecycle}
  alias Ichor.Signals

  @sweep_interval :timer.minutes(2)

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Register a RunProcess for monitoring. Call this after RunProcess starts."
  @spec monitor_run(String.t(), pid()) :: :ok
  def monitor_run(run_id, pid) do
    GenServer.cast(__MODULE__, {:monitor, run_id, pid})
  end

  @impl true
  def init(_opts) do
    schedule_sweep()
    # On init, discover and monitor all existing RunProcesses
    state = rebuild_monitors()
    Signals.emit(:mes_janitor_init, %{monitored: map_size(state)})
    {:ok, state}
  end

  @impl true
  def handle_cast({:monitor, run_id, pid}, state) do
    ref = Process.monitor(pid)
    {:noreply, Map.put(state, ref, run_id)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state, ref) do
      {nil, state} ->
        {:noreply, state}

      {run_id, state} ->
        safe_cleanup_run(run_id)
        {:noreply, state}
    end
  end

  def handle_info(:sweep, state) do
    safe_sweep()
    schedule_sweep()
    {:noreply, state}
  end

  defp safe_cleanup_run(run_id) do
    session = "mes-#{run_id}"

    # Only clean up if tmux session is actually dead.
    # MES agents are under Fleet.TeamSupervisor with liveness_poll and
    # self-terminate when their window dies. We only need to clean up
    # prompt files and any orphaned Fleet team registrations.
    if tmux_session_alive?(session) do
      Signals.emit(:mes_janitor_skipped, %{run_id: run_id, reason: "tmux_alive"})
    else
      FleetSupervisor.disband_team("mes-#{run_id}")
      TeamLifecycle.kill_session(session)
      Signals.emit(:mes_janitor_cleaned, %{run_id: run_id, trigger: "monitor"})
    end
  rescue
    e ->
      Signals.emit(:mes_janitor_error, %{
        run_id: run_id,
        reason: Exception.message(e)
      })
  end

  defp tmux_session_alive?(session) do
    Tmux.available?(session)
  end

  defp safe_sweep do
    TeamLifecycle.cleanup_orphaned_teams()
  rescue
    e ->
      Signals.emit(:mes_janitor_error, %{
        run_id: "sweep",
        reason: Exception.message(e)
      })
  end

  defp rebuild_monitors do
    RunProcess.list_all()
    |> Enum.reduce(%{}, fn {run_id, pid}, acc ->
      ref = Process.monitor(pid)
      Map.put(acc, ref, run_id)
    end)
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval)
end
