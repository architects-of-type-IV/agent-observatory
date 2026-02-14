defmodule Observatory.Annotations.Note do
  use Ash.Resource,
    domain: Observatory.Annotations,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo Observatory.Repo
    table "notes"
  end

  attributes do
    uuid_primary_key :id

    attribute :event_id, :string do
      allow_nil? false
      public? true
    end

    attribute :text, :string do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  actions do
    defaults [:read]

    create :create do
      accept [:event_id, :text]
    end

    update :update do
      accept [:text]
    end

    destroy :delete

    read :by_event do
      argument :event_id, :string, allow_nil?: false

      filter expr(event_id == ^arg(:event_id))
    end
  end

  identities do
    identity :unique_note, [:id]
  end
end
