defmodule Observatory.Events.Session do
  use Ash.Resource,
    domain: Observatory.Events,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo Observatory.Repo
    table "sessions"
  end

  attributes do
    uuid_primary_key :id

    attribute :session_id, :string do
      allow_nil? false
      public? true
    end

    attribute :source_app, :string do
      allow_nil? false
      public? true
    end

    attribute :agent_type, :string do
      public? true
    end

    attribute :model, :string do
      public? true
    end

    attribute :status, :atom do
      default :active
      public? true
      constraints one_of: [:active, :ended]
    end

    attribute :started_at, :utc_datetime do
      public? true
    end

    attribute :ended_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  actions do
    defaults [:read]

    create :create do
      accept [:session_id, :source_app, :agent_type, :model, :started_at]
      upsert? true
      upsert_identity :unique_session
    end

    update :mark_ended do
      change set_attribute(:status, :ended)
      change set_attribute(:ended_at, &DateTime.utc_now/0)
    end
  end

  identities do
    identity :unique_session, [:session_id, :source_app]
  end
end
