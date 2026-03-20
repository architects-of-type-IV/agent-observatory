defmodule Ichor.Factory.Pipeline do
  @moduledoc """
  A pipeline execution session. One per build attempt.
  Binds a set of pipeline tasks to a project and tracks overall lifecycle.
  """

  use Ash.Resource,
    domain: Ichor.Factory,
    data_layer: AshSqlite.DataLayer,
    simple_notifiers: [Ichor.Signals.FromAsh]

  alias Ichor.Factory.{Graph, PipelineTask, Spawn}

  sqlite do
    repo(Ichor.Repo)
    table("pipelines")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :label, :string do
      allow_nil?(false)
      public?(true)
      description("Human name (project title)")
    end

    attribute :source, :atom do
      allow_nil?(false)
      constraints(one_of: [:project, :imported])
      public?(true)
      description("Origin: :project (from project roadmap) or :imported (from tasks.jsonl)")
    end

    attribute :project_id, :string do
      public?(true)
      description("Project UUID (nullable, project-derived runs only)")
    end

    attribute :project_path, :string do
      public?(true)
      description("Filesystem path (nullable, imported runs only)")
    end

    attribute :tmux_session, :string do
      public?(true)
      description("Tmux session name (set by Spawner)")
    end

    attribute :status, :atom do
      allow_nil?(false)
      constraints(one_of: [:active, :completed, :failed, :archived])
      default(:active)
      public?(true)
    end

    attribute :task_count, :integer do
      default(0)
      public?(true)
    end

    timestamps()
  end

  relationships do
    has_many :pipeline_tasks, Ichor.Factory.PipelineTask do
      destination_attribute(:run_id)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:label, :source, :project_id, :project_path, :tmux_session, :status, :task_count])
    end

    update :complete do
      accept([])
      change(set_attribute(:status, :completed))
    end

    update :fail do
      accept([])
      change(set_attribute(:status, :failed))
    end

    update :archive do
      accept([])
      change(set_attribute(:status, :archived))
    end

    read :active do
      filter(expr(status == :active))
      prepare(build(sort: [inserted_at: :desc]))
    end

    read :by_project do
      argument :project_id, :string do
        allow_nil?(false)
      end

      filter(expr(project_id == ^arg(:project_id) and status == :active))
      prepare(build(sort: [inserted_at: :desc]))
    end

    read :by_path do
      argument :project_path, :string do
        allow_nil?(false)
      end

      filter(expr(project_path == ^arg(:project_path) and status == :active))
      prepare(build(sort: [inserted_at: :desc]))
    end

    action :get_run_status, :map do
      description("Get overall status and pipeline stats for a pipeline.")

      argument(:run_id, :string, allow_nil?: false)

      run(fn input, _context ->
        run_id = input.arguments.run_id

        with {:ok, run} <- __MODULE__.get(run_id),
             {:ok, pipeline_tasks} <- PipelineTask.by_run(run_id) do
          nodes = Enum.map(pipeline_tasks, &Graph.to_graph_node/1)
          stats = Graph.pipeline_stats(nodes)

          {:ok,
           %{
             "run_id" => run.id,
             "label" => run.label,
             "status" => to_string(run.status),
             "source" => to_string(run.source),
             "task_count" => run.task_count,
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
      description("Load a tasks.jsonl file into a new pipeline.")

      argument(:tasks_jsonl_path, :string, allow_nil?: false)
      argument(:label, :string, allow_nil?: false, default: "")

      run(fn input, _context ->
        opts = if input.arguments.label != "", do: [label: input.arguments.label], else: []

        case Spawn.from_file(input.arguments.tasks_jsonl_path, opts) do
          {:ok, run} ->
            {:ok,
             %{
               "run_id" => run.id,
               "label" => run.label,
               "task_count" => run.task_count,
               "status" => to_string(run.status)
             }}

          {:error, reason} ->
            {:error, "Load failed: #{inspect(reason)}"}
        end
      end)
    end

    action :export_jsonl, :map do
      description("Export all pipeline tasks for a pipeline as a JSONL string.")

      argument(:run_id, :string, allow_nil?: false)

      run(fn input, _context ->
        case PipelineTask.by_run(input.arguments.run_id) do
          {:ok, pipeline_tasks} ->
            {:ok,
             %{
               "run_id" => input.arguments.run_id,
               "jsonl" => Enum.map_join(pipeline_tasks, "\n", &task_to_jsonl/1)
             }}

          {:error, reason} ->
            {:error, "Export failed: #{inspect(reason)}"}
        end
      end)
    end
  end

  code_interface do
    define(:create)
    define(:get, action: :read, get_by: [:id])
    define(:complete)
    define(:fail)
    define(:archive)
    define(:active)
    define(:by_project, args: [:project_id])
    define(:by_path, args: [:project_path])
    define(:get_run_status, args: [:run_id])
    define(:load_jsonl, args: [:tasks_jsonl_path])
    define(:export_jsonl, args: [:run_id])
  end

  defp task_to_jsonl(task) do
    %{
      "id" => task.external_id,
      "status" => Kernel.to_string(task.status),
      "subject" => task.subject,
      "description" => task.description,
      "goal" => task.goal,
      "files" => task.allowed_files,
      "steps" => task.steps,
      "done_when" => task.done_when,
      "blocked_by" => task.blocked_by,
      "owner" => task.owner || "",
      "priority" => Kernel.to_string(task.priority),
      "wave" => task.wave,
      "phase_label" => task.phase_label,
      "acceptance_criteria" => task.acceptance_criteria,
      "tags" => task.tags,
      "notes" => task.notes || ""
    }
    |> Jason.encode!()
  end
end
