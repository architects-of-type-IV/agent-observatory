defmodule Ichor.Projects.RunProcess do
  @moduledoc """
  GenServer representing a single DAG run lifecycle.

  Responsibilities:
  - Monitors tmux session liveness (60s poll)
  - Periodic stale job detection and reset (60s)
  - Periodic health check and signal emission (30s)
  - Detects lead completion via :messages signal
  - Serializes write-through sync via handle_cast({:sync_job, job})

  Registered in Ichor.Registry via `{:dag_run, run_id}`.
  Supervised under Ichor.Projects.DynRunSupervisor (DynamicSupervisor).
  """

  use GenServer, restart: :temporary

  alias Ichor.Control.Lifecycle.TeamLaunch
  alias Ichor.Control.Lifecycle.TeamSpec
  alias Ichor.Control.Lifecycle.TmuxLauncher
  alias Ichor.Projects.{Exporter, HealthChecker, Job, Run, RunnerRegistry, RuntimeSignals}
  alias Ichor.Signals
  alias Ichor.Signals.Message

  @stale_interval_ms :timer.seconds(60)
  @health_interval_ms :timer.seconds(30)
  @liveness_interval_ms :timer.seconds(60)

  @enforce_keys [:run_id, :team_spec]
  defstruct [:run_id, :team_spec, :project_path]

  @type t :: %__MODULE__{
          run_id: String.t(),
          team_spec: TeamSpec.t(),
          project_path: String.t() | nil
        }

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    GenServer.start_link(__MODULE__, opts, name: via(run_id))
  end

  @doc "Returns the via-tuple for Registry-based name lookup."
  @spec via(String.t()) :: {:via, Registry, {Ichor.Registry, {:dag_run, String.t()}}}
  def via(run_id), do: RunnerRegistry.via(:dag_run, run_id)

  @doc "Enqueues a job for write-through sync to the project tasks.jsonl file."
  @spec sync_job(String.t(), struct() | map()) :: :ok
  def sync_job(run_id, job), do: GenServer.cast(via(run_id), {:sync_job, job})

  @impl true
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    team_spec = Keyword.fetch!(opts, :team_spec)
    project_path = Keyword.get(opts, :project_path)

    state = %__MODULE__{
      run_id: run_id,
      team_spec: team_spec,
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
        RuntimeSignals.emit_health_report(state.run_id, report.healthy, length(report.issues))

      _ ->
        :ok
    end

    schedule_health_check()
    {:noreply, state}
  end

  def handle_info(:check_liveness, state) do
    case TmuxLauncher.available?(state.team_spec.session) do
      true ->
        schedule_liveness_check()
        {:noreply, state}

      false ->
        RuntimeSignals.emit_tmux_gone(state.run_id, state.team_spec.session)
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
    coordinator_id = "#{state.team_spec.session}-coordinator"

    case from == coordinator_id do
      true ->
        with {:ok, run} <- Run.get(state.run_id) do
          Run.complete(run)
          RuntimeSignals.emit_run_completed(state.run_id, run.label)
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

  defp cleanup(state) do
    TeamLaunch.teardown(state.team_spec)
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
