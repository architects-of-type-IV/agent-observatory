defmodule Ichor.Tools.ProjectExecution do
  @moduledoc """
  MCP tools for project/DAG execution, task management, and MES floor management.

  Consolidates agent DAG execution (dag_execution), task board access (tasks),
  and Archon MES project management (mes) into one resource.
  """
  use Ash.Resource, domain: Ichor.Tools

  alias Ichor.Control.AgentProcess

  alias Ichor.Projects.{
    Exporter,
    Graph,
    Job,
    Loader,
    Project,
    Run,
    Runner,
    Scheduler,
    TeamCleanup
  }

  alias Ichor.Tasks.Board

  @project_status_map %{
    "proposed" => :proposed,
    "in_progress" => :in_progress,
    "compiled" => :compiled,
    "loaded" => :loaded,
    "failed" => :failed
  }

  actions do
    # --- DAG Execution ---

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

    # --- Task Board ---

    action :get_tasks, {:array, :map} do
      description("Get your assigned tasks from the Ichor task board.")

      argument :session_id, :string do
        allow_nil?(false)
        description("Your agent session ID")
      end

      argument :team_name, :string do
        allow_nil?(false)
        default("")
        description("Filter tasks by team name. Empty for all teams.")
      end

      run(fn input, _context ->
        session_id = input.arguments.session_id
        team_name = input.arguments[:team_name]

        tasks =
          if team_name do
            Board.list_tasks(team_name)
          else
            []
          end

        my_tasks =
          tasks
          |> Enum.filter(fn task ->
            task["owner"] == session_id || task["owner"] == nil
          end)
          |> Enum.map(fn task ->
            %{
              "id" => task["id"],
              "subject" => task["subject"],
              "status" => task["status"],
              "owner" => task["owner"],
              "description" => task["description"]
            }
          end)

        {:ok, my_tasks}
      end)
    end

    action :update_task_status, :map do
      description("Update the status of a task you are working on.")

      argument :team_name, :string do
        allow_nil?(false)
        description("The team name the task belongs to")
      end

      argument :task_id, :string do
        allow_nil?(false)
        description("The task ID to update")
      end

      argument :status, :string do
        allow_nil?(false)
        description("New status: pending, in_progress, or completed")
      end

      run(fn input, _context ->
        team = input.arguments.team_name
        task_id = input.arguments.task_id
        status = input.arguments.status

        case Board.update_task(team, task_id, %{"status" => status}) do
          {:ok, task} ->
            {:ok,
             %{
               "status" => "updated",
               "task_id" => task_id,
               "new_status" => task["status"] || status
             }}

          {:error, reason} ->
            {:error, "Failed to update task: #{inspect(reason)}"}
        end
      end)
    end

    # --- MES Floor Management ---

    action :list_projects, {:array, :map} do
      description(
        "List MES project briefs. Filter by status to see proposed, in_progress, compiled, loaded, or failed projects."
      )

      argument :status, :string do
        allow_nil?(false)

        description(
          "Filter by status: proposed, in_progress, compiled, loaded, failed. Empty string for all."
        )
      end

      run(fn input, _context ->
        projects =
          case input.arguments[:status] do
            s when s in [nil, ""] ->
              Project.list_all!()

            status_str ->
              case Map.fetch(@project_status_map, status_str) do
                {:ok, status} -> Project.by_status!(status)
                :error -> []
              end
          end

        {:ok, Enum.map(projects, &project_to_map/1)}
      end)
    end

    action :create_project, :map do
      description(
        "Create a new MES project brief. Use when an agent delivers a subsystem proposal or when you want to register a brief yourself."
      )

      argument :title, :string do
        allow_nil?(false)
        description("Short descriptive name for the subsystem")
      end

      argument :description, :string do
        allow_nil?(false)
        description("One or two sentence description of what it does")
      end

      argument :subsystem, :string do
        allow_nil?(false)
        description("Elixir module name (e.g. Ichor.Subsystems.EntropyHarvester)")
      end

      argument :signal_interface, :string do
        allow_nil?(false)
        description("How this subsystem is controlled through Ichor.Signals")
      end

      argument :topic, :string do
        allow_nil?(false)
        description("Unique PubSub topic (e.g. subsystem:correlator, empty string if none)")
      end

      argument :version, :string do
        allow_nil?(false)
        description("SemVer version string (default 0.1.0)")
      end

      argument :features, {:array, :string} do
        allow_nil?(false)
        description("List of capability descriptions (empty array if none)")
      end

      argument :use_cases, {:array, :string} do
        allow_nil?(false)
        description("Concrete scenarios where this subsystem is useful (empty array if none)")
      end

      argument :architecture, :string do
        allow_nil?(false)

        description(
          "Internal structure: processes, ETS tables, supervision (empty string if none)"
        )
      end

      argument :dependencies, {:array, :string} do
        allow_nil?(false)
        description("Ichor modules this subsystem requires (empty array if none)")
      end

      argument :signals_emitted, {:array, :string} do
        allow_nil?(false)
        description("Signal atoms this subsystem emits (empty array if none)")
      end

      argument :signals_subscribed, {:array, :string} do
        allow_nil?(false)

        description(
          "Signal atoms or categories this subsystem subscribes to (empty array if none)"
        )
      end

      argument :run_id, :string do
        allow_nil?(false)
        description("MES run ID that produced this brief (empty string if none)")
      end

      argument :team_name, :string do
        allow_nil?(false)
        description("MES team name that produced this brief (empty string if none)")
      end

      run(fn input, _context ->
        args = input.arguments

        attrs =
          %{
            title: args.title,
            description: args.description,
            subsystem: args.subsystem,
            signal_interface: args.signal_interface
          }
          |> maybe_put(:topic, args[:topic])
          |> maybe_put(:version, args[:version])
          |> maybe_put(:features, args[:features])
          |> maybe_put(:use_cases, args[:use_cases])
          |> maybe_put(:architecture, args[:architecture])
          |> maybe_put(:dependencies, args[:dependencies])
          |> maybe_put(:signals_emitted, args[:signals_emitted])
          |> maybe_put(:signals_subscribed, args[:signals_subscribed])
          |> maybe_put(:run_id, args[:run_id])
          |> maybe_put(:team_name, args[:team_name])

        case Project.create(attrs) do
          {:ok, project} -> {:ok, project_to_map(project)}
          {:error, reason} -> {:error, reason}
        end
      end)
    end

    action :check_operator_inbox, {:array, :map} do
      description(
        "Check messages sent to the operator by MES agents or other fleet members. This is YOUR inbox as floor manager. Messages are cleared after reading."
      )

      run(fn _input, _context ->
        try do
          messages = AgentProcess.get_unread("operator")

          formatted =
            Enum.map(messages, fn m ->
              %{
                "from" => m[:from] || m["from"],
                "content" => m[:content] || m["content"],
                "timestamp" => m[:timestamp] || m["timestamp"]
              }
            end)

          {:ok, formatted}
        rescue
          e in [RuntimeError, ArgumentError, KeyError] ->
            require Logger
            Logger.warning("check_operator_inbox failed: #{Exception.message(e)}")
            {:ok, []}
        end
      end)
    end

    action :mes_status, :map do
      description(
        "Get MES manufacturing pipeline status: active runs, scheduler state, team counts."
      )

      run(fn _input, _context ->
        all_runs = Runner.list_all(:mes)

        run_details =
          Enum.map(all_runs, fn {run_id, pid} ->
            deadline_passed =
              try do
                GenServer.call(pid, :deadline_passed?, 1_000)
              catch
                :exit, _ -> true
              end

            %{
              "run_id" => run_id,
              "team" => "mes-#{run_id}",
              "alive" => Process.alive?(pid),
              "past_deadline" => deadline_passed
            }
          end)

        active_count = Enum.count(run_details, fn r -> not r["past_deadline"] end)

        scheduler_status =
          try do
            Scheduler.status()
          rescue
            _ -> %{error: "Scheduler not running"}
          end

        {:ok,
         %{
           "active_runs" => active_count,
           "total_runs" => length(all_runs),
           "runs" => run_details,
           "scheduler" => scheduler_status
         }}
      end)
    end

    action :cleanup_mes, :map do
      description(
        "Force cleanup of orphaned MES teams and tmux sessions. Use when stale teams persist."
      )

      run(fn _input, _context ->
        try do
          TeamCleanup.cleanup_orphaned_teams()
          {:ok, %{"status" => "cleanup_complete"}}
        rescue
          e -> {:ok, %{"status" => "error", "reason" => Exception.message(e)}}
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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp project_to_map(project) do
    %{
      "id" => project.id,
      "title" => project.title,
      "description" => project.description,
      "subsystem" => project.subsystem,
      "signal_interface" => project.signal_interface,
      "topic" => project.topic,
      "version" => project.version,
      "features" => project.features,
      "use_cases" => project.use_cases,
      "architecture" => project.architecture,
      "dependencies" => project.dependencies,
      "signals_emitted" => project.signals_emitted,
      "signals_subscribed" => project.signals_subscribed,
      "status" => to_string(project.status),
      "team_name" => project.team_name,
      "run_id" => project.run_id,
      "created_at" => project.inserted_at
    }
  end
end
