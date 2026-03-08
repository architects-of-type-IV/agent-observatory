defmodule Observatory.Workshop.SpawnLink do
  @moduledoc """
  A spawn hierarchy link between two agent blueprints.
  from_slot spawns to_slot.
  """

  use Ash.Resource,
    domain: Observatory.Workshop,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo(Observatory.Repo)
    table("workshop_spawn_links")
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
      accept [:from_slot, :to_slot, :team_blueprint_id]
    end
  end

  code_interface do
    define :create
    define :read
    define :destroy
  end
end
