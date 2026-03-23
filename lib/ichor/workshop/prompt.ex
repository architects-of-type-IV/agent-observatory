defmodule Ichor.Workshop.Prompt do
  @moduledoc """
  A reusable prompt template.

  Simple name + content pairs for storing prompt text that can be
  referenced when configuring agents. Optional category for grouping.
  """

  use Ash.Resource,
    domain: Ichor.Workshop,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo(Ichor.Repo)
    table("workshop_prompts")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :content, :string do
      allow_nil?(false)
      default("")
      public?(true)
    end

    attribute :category, :string do
      public?(true)
    end

    timestamps()
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:name, :content, :category])
    end

    update :update do
      primary?(true)
      accept([:name, :content, :category])
    end

    read :list_all do
      prepare(build(sort: [inserted_at: :desc]))
    end
  end

  identities do
    identity(:unique_name, [:name])
  end

  code_interface do
    define(:create)
    define(:read)
    define(:update)
    define(:destroy)
    define(:by_id, action: :read, get_by: [:id])
    define(:list_all)
  end
end
