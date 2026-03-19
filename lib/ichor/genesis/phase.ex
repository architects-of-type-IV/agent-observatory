defmodule Ichor.Genesis.Phase do
  @moduledoc """
  Top-level grouping in the Mode C roadmap hierarchy.

  Phase -> Section -> Task -> Subtask.
  Belongs to a Genesis Node.
  """

  use Ash.Resource,
    domain: Ichor.Genesis,
    data_layer: AshSqlite.DataLayer,
    simple_notifiers: [Ichor.Signals.FromAsh]

  sqlite do
    repo(Ichor.Repo)
    table("genesis_phases")
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

    attribute :goals, {:array, :string} do
      public?(true)
      default([])
    end

    attribute :status, :atom do
      allow_nil?(false)
      default(:pending)
      public?(true)
      constraints(one_of: [:pending, :in_progress, :completed])
    end

    attribute :governed_by, {:array, :string} do
      public?(true)
      default([])
      description("FRD/ADR codes that govern this phase")
    end

    timestamps()
  end

  relationships do
    belongs_to :node, Ichor.Genesis.Node do
      allow_nil?(false)
      attribute_public?(true)
    end

    has_many :sections, Ichor.Genesis.Section
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:number, :title, :goals, :status, :governed_by, :node_id])
    end

    update :update do
      primary?(true)
      accept([:title, :goals, :status, :governed_by])
    end

    read :by_node do
      argument :node_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(node_id == ^arg(:node_id)))
      prepare(build(sort: [number: :asc]))
    end
  end

  code_interface do
    define(:create)
    define(:update)
    define(:get, action: :read, get_by: [:id])
    define(:by_node, args: [:node_id])
  end
end
