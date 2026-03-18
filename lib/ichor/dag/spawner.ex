defmodule Ichor.Dag.Spawner do
  @moduledoc """
  Spawns a DAG execution team inside a single tmux session.

  All agents are created upfront: coordinator, lead, and file-scoped workers.
  Worker groups are computed at spawn time from the run's job graph so jobs that
  touch the same files are assigned to the same worker for the lifetime of the run.
  """

  alias Ichor.Dag.{Graph, Job, Loader, Prompts, RunSupervisor, Validator}
  alias Ichor.Genesis.{ModeRunner, ModeSpawner}
  alias Ichor.Signals

  @spec spawn(String.t(), String.t()) ::
          {:ok, %{session: String.t(), run: map()}} | {:error, term()}
  def spawn(node_id, project_id) do
    session = "dag-#{short_id()}"
    cwd = File.cwd!()
    brief = ModeSpawner.load_project_brief(project_id)

    with {:ok, run} <- Loader.from_genesis(node_id, tmux_session: session),
         {:ok, _report} <- validate(run.id),
         {:ok, jobs} <- Job.by_run(run.id) do
      worker_groups = build_worker_groups(jobs)
      roster = team_roster(session, worker_groups)
      agents = build_agents(run, session, brief, jobs, worker_groups, roster)

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

        Signals.emit(:dag_run_ready, %{
          run_id: run.id,
          session: session,
          node_id: node_id,
          agent_count: length(agents),
          worker_count: length(worker_groups)
        })

        {:ok, %{session: session, run: run}}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_agents(run, session, brief, jobs, worker_groups, roster) do
    worker_agents =
      Enum.map(worker_groups, fn worker ->
        %{
          name: worker.name,
          capability: "builder",
          prompt:
            Prompts.worker(%{
              run_id: run.id,
              session: session,
              roster: roster,
              brief: brief,
              worker: worker
            })
        }
      end)

    [
      %{
        name: "coordinator",
        capability: "coordinator",
        prompt:
          Prompts.coordinator(%{
            run_id: run.id,
            session: session,
            roster: roster,
            brief: brief,
            jobs: jobs,
            worker_groups: worker_groups
          })
      },
      %{
        name: "lead",
        capability: "lead",
        prompt:
          Prompts.lead(%{
            run_id: run.id,
            session: session,
            roster: roster,
            brief: brief,
            jobs: jobs,
            worker_groups: worker_groups
          })
      }
      | worker_agents
    ]
  end

  defp build_worker_groups(jobs) do
    jobs
    |> Enum.sort_by(&{&1.wave || 0, &1.external_id})
    |> Enum.reduce([], &add_job_to_groups/2)
    |> Enum.map(&finalize_group/1)
    |> Enum.sort_by(&{&1.first_wave, &1.first_external_id})
    |> Enum.with_index(1)
    |> Enum.map(fn {group, index} ->
      group
      |> Map.put(:name, worker_name(index))
      |> Map.put(:capability, "builder")
    end)
  end

  defp add_job_to_groups(job, groups) do
    files = normalized_files(job.allowed_files)

    if MapSet.size(files) == 0 do
      [%{files: files, jobs: [job]} | groups]
    else
      {matching, rest} = Enum.split_with(groups, &shares_files?(&1.files, files))

      merged =
        Enum.reduce(matching, %{files: files, jobs: [job]}, fn group, acc ->
          %{
            files: MapSet.union(acc.files, group.files),
            jobs: acc.jobs ++ group.jobs
          }
        end)

      [merged | rest]
    end
  end

  defp finalize_group(group) do
    jobs = Enum.sort_by(group.jobs, &{&1.wave || 0, &1.external_id})
    first_job = hd(jobs)

    %{
      jobs: jobs,
      allowed_files: group.files |> MapSet.to_list() |> Enum.sort(),
      waves: jobs |> Enum.map(&(&1.wave || 0)) |> Enum.uniq(),
      first_wave: first_job.wave || 0,
      first_external_id: first_job.external_id
    }
  end

  defp shares_files?(group_files, job_files) do
    not MapSet.disjoint?(group_files, job_files)
  end

  defp normalized_files(files) do
    files
    |> List.wrap()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> MapSet.new()
  end

  defp worker_name(index) do
    "worker-" <> String.pad_leading(Integer.to_string(index), 2, "0")
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
