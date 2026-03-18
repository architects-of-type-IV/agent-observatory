defmodule Ichor.AgentTools.DagExecution do
  @moduledoc "MCP tools for DAG execution: claiming jobs, reporting completion, status queries, and JSONL I/O."
  use Ash.Resource, domain: Ichor.AgentTools

  alias Ichor.Dag.{Exporter, Graph, Job, Loader, Run}

  actions do
    action :next_jobs, {:array, :map} do
      description("List available (unblocked, unclaimed) jobs for a run.")

      argument(:run_id, :string, allow_nil?: false, description: "Dag.Run UUID")

      run(fn input, _context ->
        case Job.available(input.arguments.run_id) do
          {:ok, jobs} -> {:ok, Enum.map(jobs, &job_to_map/1)}
          error -> error
        end
      end)
    end

    action :claim_job, :map do
      description("Claim a pending job for this agent. Returns the full job spec.")

      argument(:job_id, :string, allow_nil?: false, description: "Dag.Job UUID")
      argument(:owner, :string, allow_nil?: false, description: "Agent session ID or name")

      run(fn input, _context ->
        args = input.arguments

        with {:ok, job} <- Job.get(args.job_id),
             {:ok, claimed} <- Job.claim(job, args.owner) do
          {:ok, job_to_map(claimed)}
        else
          {:error, %Ash.Error.Invalid{} = err} ->
            {:error, "Cannot claim job: #{format_ash_error(err)}"}

          {:error, reason} ->
            {:error, "Claim failed: #{inspect(reason)}"}
        end
      end)
    end

    action :complete_job, :map do
      description(
        "Mark a job as completed. Returns completed job, newly unblocked jobs, and whether all jobs are done."
      )

      argument(:job_id, :string, allow_nil?: false, description: "Dag.Job UUID")

      argument(:notes, :string,
        allow_nil?: true,
        description: "Completion notes or summary"
      )

      run(fn input, _context ->
        args = input.arguments

        with {:ok, job} <- Job.get(args.job_id),
             {:ok, completed} <- Job.complete(job, %{notes: args[:notes]}),
             {:ok, available} <- Job.available(completed.run_id),
             {:ok, all_jobs} <- Job.by_run(completed.run_id) do
          all_done = Enum.all?(all_jobs, &(&1.status == :completed))

          {:ok,
           %{
             "completed" => job_to_map(completed),
             "newly_unblocked" => Enum.map(available, &job_to_map/1),
             "all_done" => all_done
           }}
        else
          {:error, reason} ->
            {:error, "Complete failed: #{inspect(reason)}"}
        end
      end)
    end

    action :fail_job, :map do
      description("Mark a job as failed.")

      argument(:job_id, :string, allow_nil?: false, description: "Dag.Job UUID")
      argument(:notes, :string, allow_nil?: false, description: "Reason for failure")

      run(fn input, _context ->
        args = input.arguments

        with {:ok, job} <- Job.get(args.job_id),
             {:ok, failed} <- Job.fail(job, %{notes: args.notes}) do
          {:ok, job_to_map(failed)}
        else
          {:error, reason} ->
            {:error, "Fail action failed: #{inspect(reason)}"}
        end
      end)
    end

    action :get_run_status, :map do
      description("Get overall status and pipeline stats for a run.")

      argument(:run_id, :string, allow_nil?: false, description: "Dag.Run UUID")

      run(fn input, _context ->
        run_id = input.arguments.run_id

        with {:ok, run} <- Run.get(run_id),
             {:ok, jobs} <- Job.by_run(run_id) do
          nodes = Enum.map(jobs, &Graph.to_graph_node/1)
          stats = Graph.pipeline_stats(nodes)

          {:ok,
           %{
             "run_id" => run.id,
             "label" => run.label,
             "status" => to_string(run.status),
             "source" => to_string(run.source),
             "job_count" => run.job_count,
             "tmux_session" => run.tmux_session,
             "stats" => %{
               "total" => stats.total,
               "pending" => stats.pending,
               "in_progress" => stats.in_progress,
               "completed" => stats.completed,
               "failed" => stats.failed
             }
           }}
        else
          {:error, reason} ->
            {:error, "Status query failed: #{inspect(reason)}"}
        end
      end)
    end

    action :load_jsonl, :map do
      description(
        "Load a tasks.jsonl file into a new Dag.Run with Jobs. Returns the run_id and job count."
      )

      argument(:tasks_jsonl_path, :string,
        allow_nil?: false,
        description: "Absolute path to tasks.jsonl"
      )

      argument(:label, :string, allow_nil?: true, description: "Human label for this run")

      run(fn input, _context ->
        args = input.arguments
        opts = if args[:label], do: [label: args.label], else: []

        case Loader.from_file(args.tasks_jsonl_path, opts) do
          {:ok, run} ->
            {:ok,
             %{
               "run_id" => run.id,
               "label" => run.label,
               "job_count" => run.job_count,
               "status" => to_string(run.status)
             }}

          {:error, reason} ->
            {:error, "Load failed: #{inspect(reason)}"}
        end
      end)
    end

    action :export_jsonl, :map do
      description("Export all jobs for a run as a JSONL string.")

      argument(:run_id, :string, allow_nil?: false, description: "Dag.Run UUID")

      run(fn input, _context ->
        case Exporter.to_jsonl(input.arguments.run_id) do
          {:ok, jsonl} ->
            {:ok, %{"run_id" => input.arguments.run_id, "jsonl" => jsonl}}

          {:error, reason} ->
            {:error, "Export failed: #{inspect(reason)}"}
        end
      end)
    end
  end

  defp job_to_map(job) do
    %{
      "id" => job.id,
      "external_id" => job.external_id,
      "subject" => job.subject,
      "goal" => job.goal,
      "description" => job.description,
      "allowed_files" => job.allowed_files || [],
      "steps" => job.steps || [],
      "done_when" => job.done_when,
      "blocked_by" => job.blocked_by || [],
      "wave" => job.wave,
      "priority" => to_string(job.priority),
      "status" => to_string(job.status),
      "owner" => job.owner,
      "notes" => job.notes
    }
  end

  defp format_ash_error(%Ash.Error.Invalid{errors: errors}) do
    Enum.map_join(errors, "; ", fn e -> Map.get(e, :message, inspect(e)) end)
  end
end
