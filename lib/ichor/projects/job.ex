defmodule Ichor.Projects.Job do
  @moduledoc """
  Claimable execution unit in a DAG run. One per subtask or tasks.jsonl entry.
  Status lifecycle: pending -> in_progress -> completed/failed.
  Reset returns failed/stale jobs to pending.
  """

  use Ash.Resource,
    domain: Ichor.Projects,
    data_layer: AshSqlite.DataLayer,
    simple_notifiers: [Ichor.Signals.FromAsh]

  sqlite do
    repo(Ichor.Repo)
    table("dag_jobs")
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
      description("Genesis.Subtask UUID (nullable, genesis runs only)")
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
      description("File paths this job is scoped to")
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
    belongs_to :run, Ichor.Projects.Run do
      allow_nil?(false)
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
      prepare(Ichor.Projects.Job.Preparations.FilterAvailable)
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
      change(Ichor.Projects.Job.Changes.SyncRunProcess)
    end

    update :complete do
      require_atomic?(false)
      accept([:notes])
      change(set_attribute(:status, :completed))
      change(set_attribute(:completed_at, &__MODULE__.now/0))
      change(Ichor.Projects.Job.Changes.SyncRunProcess)
    end

    update :fail do
      require_atomic?(false)
      accept([:notes])
      change(set_attribute(:status, :failed))
      change(Ichor.Projects.Job.Changes.SyncRunProcess)
    end

    update :reset do
      require_atomic?(false)
      accept([])
      change(set_attribute(:status, :pending))
      change(set_attribute(:owner, nil))
      change(set_attribute(:claimed_at, nil))
      change(Ichor.Projects.Job.Changes.SyncRunProcess)
    end

    update :reassign do
      accept([])

      argument :owner, :string do
        allow_nil?(false)
      end

      change(atomic_update(:owner, expr(^arg(:owner))))
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
  end

  @doc false
  def now, do: DateTime.utc_now()
end
