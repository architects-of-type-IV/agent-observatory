defmodule Observatory.Messaging.Message do
  use Ash.Resource,
    domain: Observatory.Messaging,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo Observatory.Repo
    table "messages"
  end

  attributes do
    uuid_primary_key :id

    attribute :from_session_id, :string do
      allow_nil? false
      public? true
    end

    attribute :to_session_id, :string do
      allow_nil? true
      public? true
    end

    attribute :content, :string do
      allow_nil? false
      public? true
    end

    attribute :message_type, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
        :message,
        :broadcast,
        :shutdown_request,
        :shutdown_response,
        :plan_approval_request,
        :plan_approval_response
      ]
    end

    attribute :read, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :team_name, :string do
      allow_nil? true
      public? true
    end

    timestamps()
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :from_session_id,
        :to_session_id,
        :content,
        :message_type,
        :read,
        :team_name
      ]
    end

    update :mark_read do
      accept []
      change set_attribute(:read, true)
    end

    read :unread_for_session do
      argument :session_id, :string, allow_nil?: false

      filter expr(
        to_session_id == ^arg(:session_id) and read == false
      )
    end

    read :by_thread do
      argument :session_a, :string, allow_nil?: false
      argument :session_b, :string, allow_nil?: false

      filter expr(
        (from_session_id == ^arg(:session_a) and to_session_id == ^arg(:session_b)) or
        (from_session_id == ^arg(:session_b) and to_session_id == ^arg(:session_a))
      )
    end
  end

  identities do
    identity :unique_message, [:id]
  end
end
