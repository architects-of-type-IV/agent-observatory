defmodule Ichor.Genesis.Section do
  @moduledoc """
  Section within a Phase in the Mode C roadmap.

  Phase -> Section -> Task -> Subtask.
  Belongs to a Phase (by phase_id).
  """

  use Ash.Resource,
    domain: Ichor.Genesis,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo(Ichor.Repo)
    table("genesis_sections")
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

    timestamps()
  end

  relationships do
    belongs_to :phase, Ichor.Genesis.Phase do
      allow_nil?(false)
      attribute_public?(true)
    end

    has_many :tasks, Ichor.Genesis.Task
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:number, :title, :goal, :phase_id])
    end

    update :update do
      primary?(true)
      accept([:title, :goal])
    end

    read :by_phase do
      argument :phase_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(phase_id == ^arg(:phase_id)))
      prepare(build(sort: [number: :asc]))
    end
  end

  code_interface do
    define(:create)
    define(:update)
    define(:get, action: :read, get_by: [:id])
    define(:by_phase, args: [:phase_id])
  end
end
