defmodule Ichor.Projects.RoadmapTask do
  @moduledoc """
  Task within a Section in the Mode C roadmap.

  Phase -> Section -> Task -> Subtask.
  Belongs to a Section (by section_id).
  """

  use Ash.Resource,
    domain: Ichor.Projects,
    data_layer: AshSqlite.DataLayer,
    simple_notifiers: [Ichor.Signals.FromAsh]

  sqlite do
    repo(Ichor.Repo)
    table("genesis_tasks")
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

    attribute :governed_by, {:array, :string} do
      public?(true)
      default([])
      description("FRD/ADR codes governing this task")
    end

    attribute :parent_uc, :string do
      public?(true)
      description("UseCase code this task implements")
    end

    attribute :status, Ichor.Projects.Types.WorkStatus do
      allow_nil?(false)
      default(:pending)
      public?(true)
    end

    timestamps()
  end

  relationships do
    belongs_to :section, Ichor.Projects.Section do
      allow_nil?(false)
      attribute_public?(true)
    end

    has_many :subtasks, Ichor.Projects.Subtask do
      destination_attribute(:task_id)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:number, :title, :governed_by, :parent_uc, :status, :section_id])
    end

    update :update do
      primary?(true)
      accept([:title, :governed_by, :parent_uc, :status])
    end

    read :by_section do
      argument :section_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(section_id == ^arg(:section_id)))
      prepare(build(sort: [number: :asc]))
    end
  end

  code_interface do
    define(:create)
    define(:update)
    define(:get, action: :read, get_by: [:id])
    define(:by_section, args: [:section_id])
  end
end
