defmodule Ichor.Projects.Spawner do
  @moduledoc """
  Spawns a DAG execution team inside a single tmux session.

  All agents are created upfront: coordinator, lead, and file-scoped workers.
  Worker groups are computed at spawn time from the run's job graph so jobs that
  touch the same files are assigned to the same worker for the lifetime of the run.
  """

  alias Ichor.Control.Lifecycle.TeamLaunch

  alias Ichor.Projects.{
    DagTeamSpecBuilder,
    Graph,
    Job,
    Loader,
    ModeSpawner,
    RunSupervisor,
    RuntimeSignals,
    Validator,
    WorkerGroups
  }

  alias Ichor.Projects.SubsystemScaffold

  @doc "Spawns a full DAG execution team for the given genesis node and project."
  @spec spawn(String.t(), String.t()) ::
          {:ok, %{session: String.t(), run: map()}} | {:error, term()}
  def spawn(node_id, project_id) do
    session = "dag-#{short_id()}"
    brief = ModeSpawner.load_project_brief(project_id)

    with {:ok, node} <- Ichor.Projects.get_node(node_id),
         {app_name, module_name} = SubsystemScaffold.derive_names(node.title),
         subsystem_dir = SubsystemScaffold.subsystem_path(app_name),
         {:ok, _path} <- SubsystemScaffold.scaffold(app_name, module_name),
         {:ok, run} <- Loader.from_genesis(node_id, tmux_session: session),
         {:ok, _report} <- validate(run.id),
         {:ok, jobs} <- Job.by_run(run.id) do
      worker_groups = build_worker_groups(jobs)
      prompt_ctx = %{subsystem_dir: subsystem_dir, module_name: module_name}

      spec =
        DagTeamSpecBuilder.build_team_spec(run, session, brief, jobs, worker_groups, prompt_ctx)

      with {:ok, ^session} <- TeamLaunch.launch(spec) do
        RunSupervisor.start_run(
          run_id: run.id,
          team_spec: spec,
          project_path: run.project_path
        )

        RuntimeSignals.emit_run_ready(
          run.id,
          session,
          node_id,
          length(spec.agents),
          length(worker_groups)
        )

        {:ok, %{session: session, run: run}}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_worker_groups(jobs) do
    jobs
    |> Enum.sort_by(&{&1.wave || 0, &1.external_id})
    |> WorkerGroups.group()
    |> Enum.map(&enrich_group/1)
  end

  defp enrich_group(group) do
    %{
      name: group.name,
      capability: "builder",
      jobs: group.jobs,
      allowed_files: Enum.sort(group.files),
      waves: group.jobs |> Enum.map(&(&1.wave || 0)) |> Enum.uniq()
    }
  end

  defp validate(run_id) do
    case Job.by_run(run_id) do
      {:ok, jobs} ->
        items = Enum.map(jobs, &Graph.to_graph_node/1)
        cycles = Validator.detect_cycles(items)
        missing = Validator.flat_dag_check(items)

        case {cycles, missing} do
          {[], []} -> {:ok, %{cycles: [], missing_refs: []}}
          _ -> {:error, %{cycles: cycles, missing_refs: missing}}
        end

      error ->
        error
    end
  end

  defp short_id, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
end
