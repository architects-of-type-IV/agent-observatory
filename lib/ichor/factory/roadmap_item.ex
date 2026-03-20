defmodule Ichor.Factory.RoadmapItem do
  @moduledoc """
  Unified roadmap item: phase, section, task, or subtask.

  Replaces the four-resource hierarchy (Phase / Section / RoadmapTask / Subtask)
  with a self-referential tree rooted at a Genesis Node.

  Tree shape:
    node_id (Genesis Node)
      └─ kind: :phase    (parent_id: nil)
           └─ kind: :section  (parent_id: phase.id)
                └─ kind: :task    (parent_id: section.id)
                     └─ kind: :subtask  (parent_id: task.id)

  Type-specific fields are nullable and only populated for the relevant kind:
    - :phase    → goals, governed_by
    - :section  → goal
    - :task     → governed_by, parent_uc
    - :subtask  → goal, allowed_files, blocked_by, steps, done_when, owner
  """

  use Ash.Resource,
    domain: Ichor.Factory,
    data_layer: AshSqlite.DataLayer,
    simple_notifiers: [Ichor.Signals.FromAsh]

  sqlite do
    repo(Ichor.Repo)
    table("genesis_roadmap_items")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :kind, :atom do
      allow_nil?(false)
      public?(true)
      constraints(one_of: [:phase, :section, :task, :subtask])
    end

    attribute :number, :integer do
      allow_nil?(false)
      public?(true)
    end

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :status, Ichor.Factory.Types.WorkStatus do
      allow_nil?(false)
      default(:pending)
      public?(true)
    end

    # Shared: phases and tasks
    attribute :governed_by, {:array, :string} do
      public?(true)
      default([])
      description("FRD/ADR codes governing this item")
    end

    # Phases only
    attribute :goals, {:array, :string} do
      public?(true)
      default([])
    end

    # Sections and subtasks
    attribute :goal, :string do
      public?(true)
    end

    # Tasks only
    attribute :parent_uc, :string do
      public?(true)
      description("UseCase code this task implements")
    end

    # Subtasks only
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

    attribute :owner, :string do
      public?(true)
      description("Agent session assigned to this subtask")
    end

    timestamps()
  end

  relationships do
    belongs_to :node, Ichor.Factory.Node do
      allow_nil?(false)
      attribute_public?(true)
    end

    belongs_to :parent, Ichor.Factory.RoadmapItem do
      allow_nil?(true)
      attribute_public?(true)
      source_attribute(:parent_id)
      destination_attribute(:id)
    end

    has_many :children, Ichor.Factory.RoadmapItem do
      source_attribute(:id)
      destination_attribute(:parent_id)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :kind,
        :number,
        :title,
        :status,
        :governed_by,
        :goals,
        :goal,
        :parent_uc,
        :allowed_files,
        :blocked_by,
        :steps,
        :done_when,
        :owner,
        :node_id,
        :parent_id
      ])
    end

    update :update do
      primary?(true)

      accept([
        :title,
        :status,
        :governed_by,
        :goals,
        :goal,
        :parent_uc,
        :allowed_files,
        :blocked_by,
        :steps,
        :done_when,
        :owner
      ])
    end

    read :by_node do
      argument :node_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(node_id == ^arg(:node_id)))
      prepare(build(sort: [number: :asc]))
    end

    read :by_node_and_kind do
      argument :node_id, :uuid do
        allow_nil?(false)
      end

      argument :kind, :atom do
        allow_nil?(false)
        constraints(one_of: [:phase, :section, :task, :subtask])
      end

      filter(expr(node_id == ^arg(:node_id) and kind == ^arg(:kind)))
      prepare(build(sort: [number: :asc]))
    end

    read :phases_with_hierarchy do
      argument :node_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(node_id == ^arg(:node_id) and kind == :phase))

      prepare(
        build(
          sort: [number: :asc],
          load: [children: [children: [children: :children]]]
        )
      )
    end

    read :by_parent do
      argument :parent_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(parent_id == ^arg(:parent_id)))
      prepare(build(sort: [number: :asc]))
    end
  end

  code_interface do
    define(:create)
    define(:update)
    define(:get, action: :read, get_by: [:id])
    define(:by_node, args: [:node_id])
    define(:by_node_and_kind, args: [:node_id, :kind])
    define(:phases_with_hierarchy, args: [:node_id])
    define(:by_parent, args: [:parent_id])
  end
end
