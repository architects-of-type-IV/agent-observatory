defmodule Ichor.Dag.RunProcess do
  @moduledoc """
  GenServer representing a single DAG run lifecycle.

  Responsibilities:
  - Monitors tmux session liveness (60s poll)
  - Periodic stale job detection and reset (60s)
  - Periodic health check and signal emission (30s)
  - Detects lead completion via :messages signal
  - Serializes write-through sync via handle_cast({:sync_job, job})

  Registered in Ichor.Registry via `{:dag_run, run_id}`.
  Supervised under Ichor.Dag.DynRunSupervisor (DynamicSupervisor).
  """

  use GenServer, restart: :temporary

  alias Ichor.Dag.{Exporter, HealthChecker, Job, Run}
  alias Ichor.Fleet.FleetSupervisor
  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.Genesis.ModeRunner
  alias Ichor.Signals
  alias Ichor.Signals.Message

  @stale_interval_ms :timer.seconds(60)
  @health_interval_ms :timer.seconds(30)
  @liveness_interval_ms :timer.seconds(60)

  defstruct [:run_id, :tmux_session, :project_path]

  # ── Public API ────────────────────────────────────────────────────────

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    GenServer.start_link(__MODULE__, opts, name: via(run_id))
  end

  @spec via(String.t()) :: {:via, Registry, {Ichor.Registry, {:dag_run, String.t()}}}
  def via(run_id), do: {:via, Registry, {Ichor.Registry, {:dag_run, run_id}}}

  @spec sync_job(String.t(), Ichor.Dag.Job.t()) :: :ok
  def sync_job(run_id, job), do: GenServer.cast(via(run_id), {:sync_job, job})

  # ── GenServer Callbacks ───────────────────────────────────────────────

  @impl true
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    tmux_session = Keyword.fetch!(opts, :tmux_session)
    project_path = Keyword.get(opts, :project_path)

    state = %__MODULE__{
      run_id: run_id,
      tmux_session: tmux_session,
      project_path: project_path
    }

    Signals.subscribe(:messages)
    schedule_stale_check()
    schedule_health_check()
    schedule_liveness_check()

    {:ok, state}
  end

  @impl true
  def handle_info(:check_stale, state) do
    with {:ok, jobs} <- Job.by_run(state.run_id) do
      now = DateTime.utc_now()
      stale = Enum.filter(jobs, &(to_string(&1.status) == "in_progress" and stale?(&1, now)))
      Enum.each(stale, &Job.reset/1)
    end

    schedule_stale_check()
    {:noreply, state}
  end

  def handle_info(:check_health, state) do
    case HealthChecker.check(state.run_id) do
      {:ok, report} ->
        Signals.emit(:dag_health_report, %{
          run_id: state.run_id,
          healthy: report.healthy,
          issue_count: length(report.issues)
        })

      _ ->
        :ok
    end

    schedule_health_check()
    {:noreply, state}
  end

  def handle_info(:check_liveness, state) do
    case Tmux.available?(state.tmux_session) do
      true ->
        schedule_liveness_check()
        {:noreply, state}

      false ->
        Signals.emit(:dag_tmux_gone, %{run_id: state.run_id, session: state.tmux_session})
        cleanup(state)
        {:stop, :normal, state}
    end
  end

  def handle_info(
        %Message{
          name: :message_delivered,
          data: %{msg_map: %{to: "operator", from: from}}
        },
        state
      )
      when is_binary(from) do
    coordinator_id = "#{state.tmux_session}-coordinator"

    case from == coordinator_id do
      true ->
        with {:ok, run} <- Run.get(state.run_id) do
          Run.complete(run)

          Signals.emit(:dag_run_completed, %{
            run_id: state.run_id,
            label: run.label
          })
        end

        cleanup(state)
        {:stop, :normal, state}

      false ->
        {:noreply, state}
    end
  end

  def handle_info(%Message{}, state), do: {:noreply, state}

  @impl true
  def handle_cast({:sync_job, job}, state) do
    Task.start(fn -> Exporter.sync_to_file(job, state.project_path) end)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state), do: :ok

  # ── Private ───────────────────────────────────────────────────────────

  defp cleanup(state) do
    ModeRunner.kill_session(state.tmux_session, state.run_id, "dag")
    FleetSupervisor.disband_team(state.tmux_session)
  end

  defp schedule_stale_check do
    Process.send_after(self(), :check_stale, @stale_interval_ms)
  end

  defp schedule_health_check do
    Process.send_after(self(), :check_health, @health_interval_ms)
  end

  defp schedule_liveness_check do
    Process.send_after(self(), :check_liveness, @liveness_interval_ms)
  end

  defp stale?(job, now, threshold_min \\ 10) do
    case job.updated_at do
      nil -> true
      ts -> DateTime.diff(now, ts, :minute) > threshold_min
    end
  end
end
