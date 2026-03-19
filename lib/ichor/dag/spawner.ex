defmodule Ichor.Dag.Spawner do
  @moduledoc """
  Spawns a DAG execution team inside a single tmux session.

  All agents are created upfront: coordinator, lead, and file-scoped workers.
  Worker groups are computed at spawn time from the run's job graph so jobs that
  touch the same files are assigned to the same worker for the lifetime of the run.
  """

  alias Ichor.Dag.{
    Graph,
    Handoff,
    Job,
    Loader,
    Prompts,
    RunSupervisor,
    RuntimeSignals,
    Validator,
    WorkerGroups
  }

  alias Ichor.Genesis.{ModeRunner, ModeSpawner}
  alias Ichor.Mes.SubsystemScaffold

  @spec spawn(String.t(), String.t()) ::
          {:ok, %{session: String.t(), run: map()}} | {:error, term()}
  def spawn(node_id, project_id) do
    session = "dag-#{short_id()}"
    cwd = File.cwd!()
    brief = ModeSpawner.load_project_brief(project_id)

    with {:ok, node} <- Ichor.Genesis.get_node(node_id),
         {app_name, module_name} = SubsystemScaffold.derive_names(node.title),
         subsystem_dir = SubsystemScaffold.subsystem_path(app_name),
         {:ok, _path} <- SubsystemScaffold.scaffold(app_name, module_name),
         {:ok, run} <- Loader.from_genesis(node_id, tmux_session: session),
         {:ok, _report} <- validate(run.id),
         {:ok, jobs} <- Job.by_run(run.id) do
      worker_groups = build_worker_groups(jobs)
      roster = team_roster(session, worker_groups)
      prompt_ctx = %{subsystem_dir: subsystem_dir, module_name: module_name}
      _handoff = Handoff.package_jobs(run.id, jobs)
      agents = build_agents(run, session, brief, jobs, worker_groups, roster, prompt_ctx)

      with :ok <- ModeRunner.write_agent_scripts(run.id, "dag", agents),
           :ok <- ModeRunner.create_session_with_agent(session, cwd, run.id, "dag", hd(agents)),
           :ok <-
             ModeRunner.create_remaining_windows(session, cwd, run.id, "dag", tl(agents)) do
        Enum.each(agents, &ModeRunner.register_agent(session, &1, session, run.id, cwd))

        RunSupervisor.start_run(
          run_id: run.id,
          tmux_session: session,
          project_path: run.project_path
        )

        RuntimeSignals.emit_run_ready(
          run.id,
          session,
          node_id,
          length(agents),
          length(worker_groups)
        )

        {:ok, %{session: session, run: run}}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_agents(run, session, brief, jobs, worker_groups, roster, prompt_ctx) do
    shared = %{
      run_id: run.id,
      session: session,
      roster: roster,
      brief: brief,
      subsystem_dir: prompt_ctx.subsystem_dir
    }

    worker_agents =
      Enum.map(worker_groups, fn worker ->
        %{
          name: worker.name,
          capability: "builder",
          prompt: Prompts.worker(Map.put(shared, :worker, worker))
        }
      end)

    [
      %{
        name: "coordinator",
        capability: "coordinator",
        prompt:
          Prompts.coordinator(Map.merge(shared, %{jobs: jobs, worker_groups: worker_groups}))
      },
      %{
        name: "lead",
        capability: "lead",
        prompt: Prompts.lead(Map.merge(shared, %{jobs: jobs, worker_groups: worker_groups}))
      }
      | worker_agents
    ]
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

  defp team_roster(session, worker_groups) do
    names = ["coordinator", "lead"] ++ Enum.map(worker_groups, & &1.name)

    ids = Enum.map_join(names, "\n", fn name -> "  - #{name}: #{session}-#{name}" end)

    """
    TEAM ROSTER (use EXACT IDs with send_message/check_inbox):
    #{ids}
      - operator: operator
    Your session ID is: #{session}-YOUR_NAME
    """
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
