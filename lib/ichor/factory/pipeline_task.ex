defmodule Ichor.Factory.PipelineTask do
  @moduledoc """
  Claimable execution unit in a pipeline. One per roadmap task or tasks.jsonl entry.
  Status lifecycle: pending -> in_progress -> completed/failed.
  Reset returns failed or stale pipeline tasks to pending.
  """

  import Ichor.Util, only: [blank_to_nil: 1]

  use Ash.Resource,
    domain: Ichor.Factory,
    data_layer: AshSqlite.DataLayer,
    simple_notifiers: [
      Ichor.Signals.FromAsh,
      Ichor.Factory.PipelineTask.Notifiers.SyncRunner
    ]

  sqlite do
    repo(Ichor.Repo)
    table("pipeline_tasks")
  end

  identities do
    identity(:run_external, [:run_id, :external_id])
  end

  attributes do
    uuid_primary_key(:id)

    attribute :external_id, :string do
      allow_nil?(false)
      public?(true)
      description("Original ID from source (dotted '1.2.3.4' or monotonic '42')")
    end

    attribute :subtask_id, :string do
      public?(true)
      description("Roadmap subtask UUID (nullable, project-derived runs only)")
    end

    attribute :subject, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute(:description, :string, public?: true)
    attribute(:goal, :string, public?: true)

    attribute :allowed_files, {:array, :string} do
      default([])
      public?(true)
      description("File paths this task is scoped to")
    end

    attribute :steps, {:array, :string} do
      default([])
      public?(true)
    end

    attribute :done_when, :string do
      public?(true)
      description("Verification command")
    end

    attribute :blocked_by, {:array, :string} do
      default([])
      public?(true)
      description("external_id strings within same run")
    end

    attribute :status, :atom do
      allow_nil?(false)
      constraints(one_of: [:pending, :in_progress, :completed, :failed])
      default(:pending)
      public?(true)
    end

    attribute :owner, :string do
      public?(true)
      description("Agent session ID")
    end

    attribute :priority, :atom do
      allow_nil?(false)
      constraints(one_of: [:critical, :high, :medium, :low])
      default(:medium)
      public?(true)
    end

    attribute :wave, :integer do
      public?(true)
      description("Topological execution wave -- same wave = parallelizable")
    end

    attribute :acceptance_criteria, {:array, :string} do
      default([])
      public?(true)
    end

    attribute :phase_label, :string do
      public?(true)
      description("Phase/epic label")
    end

    attribute(:tags, {:array, :string}, default: [], public?: true)
    attribute(:notes, :string, public?: true)

    attribute(:claimed_at, :utc_datetime_usec, public?: true)
    attribute(:completed_at, :utc_datetime_usec, public?: true)

    timestamps()
  end

  relationships do
    belongs_to :pipeline, Ichor.Factory.Pipeline do
      allow_nil?(false)
      source_attribute(:run_id)
      attribute_public?(true)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :external_id,
        :subtask_id,
        :subject,
        :description,
        :goal,
        :allowed_files,
        :steps,
        :done_when,
        :blocked_by,
        :status,
        :owner,
        :priority,
        :wave,
        :acceptance_criteria,
        :phase_label,
        :tags,
        :notes,
        :run_id
      ])
    end

    read :by_run do
      argument :run_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(run_id == ^arg(:run_id)))
      prepare(build(sort: [wave: :asc, external_id: :asc]))
    end

    read :available do
      argument :run_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(run_id == ^arg(:run_id) and status == :pending and is_nil(owner)))
      prepare(Ichor.Factory.PipelineTask.Preparations.FilterAvailable)
    end

    update :claim do
      require_atomic?(false)
      accept([])

      argument :owner, :string do
        allow_nil?(false)
      end

      validate(attribute_equals(:status, :pending))
      validate(attribute_equals(:owner, nil))

      change(set_attribute(:status, :in_progress))
      change(set_attribute(:claimed_at, &__MODULE__.now/0))
      change(atomic_update(:owner, expr(^arg(:owner))))
    end

    update :complete do
      require_atomic?(false)
      accept([:notes])
      change(set_attribute(:status, :completed))
      change(set_attribute(:completed_at, &__MODULE__.now/0))
    end

    update :fail do
      accept([:notes])
      change(set_attribute(:status, :failed))
    end

    update :reset do
      accept([])
      change(set_attribute(:status, :pending))
      change(set_attribute(:owner, nil))
      change(set_attribute(:claimed_at, nil))
    end

    update :reassign do
      accept([])

      argument :owner, :string do
        allow_nil?(false)
      end

      change(atomic_update(:owner, expr(^arg(:owner))))
    end

    action :next_tasks, {:array, :map} do
      description("List available tasks for a pipeline.")

      argument(:run_id, :string, allow_nil?: false)

      run(fn input, _context ->
        with {:ok, tasks} <-
               __MODULE__
               |> Ash.Query.for_read(:available, %{run_id: input.arguments.run_id})
               |> Ash.read() do
          {:ok, Enum.map(tasks, &task_to_map/1)}
        end
      end)
    end

    action :claim_task, :map do
      description("Claim a pending task and return the full task spec.")

      argument(:task_id, :string, allow_nil?: false)
      argument(:owner, :string, allow_nil?: false)

      run(fn input, _context ->
        with {:ok, task} <- Ash.get(__MODULE__, input.arguments.task_id),
             {:ok, claimed} <-
               task
               |> Ash.Changeset.for_update(:claim, %{owner: input.arguments.owner})
               |> Ash.update() do
          {:ok, task_to_map(claimed)}
        else
          {:error, %Ash.Error.Invalid{} = err} ->
            {:error, "Cannot claim task: #{format_ash_error(err)}"}

          {:error, reason} ->
            {:error, "Claim failed: #{inspect(reason)}"}
        end
      end)
    end

    action :complete_task, :map do
      description("Mark a task as completed and report newly unblocked tasks.")

      argument(:task_id, :string, allow_nil?: false)
      argument(:notes, :string, allow_nil?: false, default: "")

      run(fn input, _context ->
        with {:ok, task} <- Ash.get(__MODULE__, input.arguments.task_id),
             {:ok, completed} <-
               task
               |> Ash.Changeset.for_update(:complete, %{
                 notes: blank_to_nil(input.arguments.notes)
               })
               |> Ash.update(),
             {:ok, all_tasks} <-
               __MODULE__
               |> Ash.Query.for_read(:by_run, %{run_id: completed.run_id})
               |> Ash.read() do
          completed_ids =
            all_tasks
            |> Enum.filter(&(&1.status == :completed))
            |> MapSet.new(& &1.external_id)

          available =
            Enum.filter(all_tasks, fn t ->
              t.status == :pending and is_nil(t.owner) and
                Enum.all?(t.blocked_by, &MapSet.member?(completed_ids, &1))
            end)

          {:ok,
           %{
             "completed" => task_to_map(completed),
             "newly_unblocked" => Enum.map(available, &task_to_map/1),
             "all_done" => Enum.all?(all_tasks, &(&1.status == :completed))
           }}
        else
          {:error, reason} ->
            {:error, "Complete failed: #{inspect(reason)}"}
        end
      end)
    end

    action :fail_task, :map do
      description("Mark a task as failed.")

      argument(:task_id, :string, allow_nil?: false)
      argument(:notes, :string, allow_nil?: false)

      run(fn input, _context ->
        with {:ok, task} <- Ash.get(__MODULE__, input.arguments.task_id),
             {:ok, failed} <-
               task
               |> Ash.Changeset.for_update(:fail, %{notes: input.arguments.notes})
               |> Ash.update() do
          {:ok, task_to_map(failed)}
        else
          {:error, reason} ->
            {:error, "Fail action failed: #{inspect(reason)}"}
        end
      end)
    end
  end

  code_interface do
    define(:create)
    define(:get, action: :read, get_by: [:id])
    define(:by_run, args: [:run_id])
    define(:available, args: [:run_id])
    define(:claim, args: [:owner])
    define(:complete)
    define(:fail)
    define(:reset)
    define(:reassign, args: [:owner])
    define(:next_tasks, args: [:run_id])
    define(:claim_task, args: [:task_id, :owner])
    define(:complete_task, args: [:task_id])
    define(:fail_task, args: [:task_id, :notes])
  end

  @doc false
  def now, do: DateTime.utc_now()

  defp task_to_map(task) do
    %{
      "id" => task.id,
      "external_id" => task.external_id,
      "subject" => task.subject,
      "goal" => task.goal,
      "description" => task.description,
      "allowed_files" => task.allowed_files || [],
      "steps" => task.steps || [],
      "done_when" => task.done_when,
      "blocked_by" => task.blocked_by || [],
      "wave" => task.wave,
      "priority" => to_string(task.priority),
      "status" => to_string(task.status),
      "owner" => task.owner,
      "notes" => task.notes
    }
  end

  defp format_ash_error(%Ash.Error.Invalid{errors: errors}) do
    Enum.map_join(errors, "; ", fn e -> Map.get(e, :message, inspect(e)) end)
  end
end
