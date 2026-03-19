defmodule Ichor.Projects.Subtask do
  @moduledoc """
  Atomic unit of work in the Mode C roadmap. DAG-ready.

  Phase -> Section -> Task -> Subtask.
  Belongs to a Task (by task_id). Contains enough detail
  for a worker agent to execute autonomously.
  """

  use Ash.Resource,
    domain: Ichor.Projects,
    data_layer: AshSqlite.DataLayer,
    simple_notifiers: [Ichor.Signals.FromAsh]

  sqlite do
    repo(Ichor.Repo)
    table("genesis_subtasks")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :number, :integer do
      allow_nil?(false)
      public?(true)
    end

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :goal, :string do
      public?(true)
    end

    attribute :allowed_files, {:array, :string} do
      public?(true)
      default([])
      description("File paths this subtask is scoped to")
    end

    attribute :blocked_by, {:array, :string} do
      public?(true)
      default([])
      description("Subtask IDs that must complete first")
    end

    attribute :steps, {:array, :string} do
      public?(true)
      default([])
      description("Ordered implementation steps")
    end

    attribute :done_when, :string do
      public?(true)
      description("Verification command, e.g. mix compile --warnings-as-errors")
    end

    attribute :status, Ichor.Projects.Types.WorkStatus do
      allow_nil?(false)
      default(:pending)
      public?(true)
    end

    attribute :owner, :string do
      public?(true)
      description("Agent session assigned to this subtask")
    end

    timestamps()
  end

  relationships do
    belongs_to :task, Ichor.Projects.RoadmapTask do
      allow_nil?(false)
      attribute_public?(true)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :number,
        :title,
        :goal,
        :allowed_files,
        :blocked_by,
        :steps,
        :done_when,
        :status,
        :owner,
        :task_id
      ])
    end

    update :update do
      primary?(true)
      accept([:title, :goal, :allowed_files, :blocked_by, :steps, :done_when, :status, :owner])
    end

    read :by_task do
      argument :task_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(task_id == ^arg(:task_id)))
      prepare(build(sort: [number: :asc]))
    end
  end

  code_interface do
    define(:create)
    define(:update)
    define(:get, action: :read, get_by: [:id])
    define(:by_task, args: [:task_id])
  end
end
