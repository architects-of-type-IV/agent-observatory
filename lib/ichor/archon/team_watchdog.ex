defmodule Ichor.Archon.TeamWatchdog do
  @moduledoc """
  Monitors team lifecycle across all team types (DAG, Genesis, MES).
  Detects unexpected deaths, archives runs, resets jobs, notifies operator.
  Pure decision logic in Reactions module; this GenServer is orchestration only.
  """

  use GenServer

  alias Ichor.Archon.TeamWatchdog.Reactions
  alias Ichor.Dag.{Job, Run}
  alias Ichor.Fleet.FleetSupervisor
  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.Signals
  alias Ichor.Signals.Message

  @sweep_interval_ms :timer.minutes(2)
  @inbox_dir Path.expand("~/.claude/inbox")

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Signals.subscribe(:fleet)
    Signals.subscribe(:dag)
    Signals.subscribe(:genesis)
    Signals.subscribe(:monitoring)
    schedule_sweep()
    {:ok, %{completed_runs: MapSet.new()}}
  end

  @impl true
  def handle_info(%Message{name: name, data: data}, state) do
    {actions, new_state} = Reactions.react(name, data, state)
    Enum.each(actions, &dispatch/1)
    {:noreply, new_state}
  end

  def handle_info(:sweep, state) do
    run_checks = check_active_runs()
    {actions, new_state} = Reactions.react_sweep(run_checks, state)
    Enum.each(actions, &dispatch/1)

    Signals.emit(:watchdog_sweep, %{orphaned_count: length(actions)})
    schedule_sweep()
    {:noreply, new_state}
  end

  def handle_info(_, state), do: {:noreply, state}

  # ── Dispatch (side effects isolated here) ────────────────────────

  defp dispatch(:noop), do: :ok

  defp dispatch({:archive_run, run_id}) do
    case Run.get(run_id) do
      {:ok, %{status: :active} = run} ->
        Run.archive(run)
        Signals.emit(:dag_run_archived, %{run_id: run_id, label: run.label, reason: "watchdog"})

      _ ->
        :ok
    end
  end

  defp dispatch({:reset_jobs, run_id}) do
    case Job.by_run(run_id) do
      {:ok, jobs} ->
        jobs
        |> Enum.filter(&(&1.status == :in_progress))
        |> Enum.each(&Job.reset/1)

      _ ->
        :ok
    end
  end

  defp dispatch({:disband_team, session}) do
    FleetSupervisor.disband_team(session)
  end

  defp dispatch({:notify_operator, message}) do
    write_inbox_notification(message)
  end

  # ── Sweep ────────────────────────────────────────────────────────

  defp check_active_runs do
    case Run.active() do
      {:ok, runs} ->
        Enum.map(runs, fn run ->
          {run.id, run.tmux_session, Tmux.available?(run.tmux_session)}
        end)

      _ ->
        []
    end
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval_ms)

  defp write_inbox_notification(message) do
    File.mkdir_p!(@inbox_dir)

    notification = %{
      type: "team_watchdog",
      message: message,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    path = Path.join(@inbox_dir, "watchdog-#{System.unique_integer([:positive])}.json")
    File.write!(path, Jason.encode!(notification))
  end
end
