defmodule Observatory.Workshop.CommRule do
  @moduledoc """
  A communication rule between two agent blueprints.
  Policies: allow, deny, route (with optional via_slot).
  """

  use Ash.Resource,
    domain: Observatory.Workshop,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo(Observatory.Repo)
    table("workshop_comm_rules")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :from_slot, :integer do
      allow_nil?(false)
      public?(true)
    end

    attribute :to_slot, :integer do
      allow_nil?(false)
      public?(true)
    end

    attribute :policy, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :via_slot, :integer do
      public?(true)
      description "For route policy: the intermediary agent slot"
    end

    timestamps()
  end

  relationships do
    belongs_to :team_blueprint, Observatory.Workshop.TeamBlueprint do
      allow_nil?(false)
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:from_slot, :to_slot, :policy, :via_slot, :team_blueprint_id]
    end

    update :update do
      primary? true
      accept [:from_slot, :to_slot, :policy, :via_slot]
    end
  end

  code_interface do
    define :create
    define :read
    define :destroy
  end
end
