defmodule Observatory.TaskBoard.Task do
  use Ash.Resource,
    domain: Observatory.TaskBoard,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo Observatory.Repo
    table "tasks"
  end

  attributes do
    uuid_primary_key :id

    attribute :subject, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      allow_nil? true
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true

      constraints one_of: [
        :pending,
        :in_progress,
        :completed
      ]
    end

    attribute :owner, :string do
      allow_nil? true
      public? true
    end

    attribute :team_name, :string do
      allow_nil? true
      public? true
    end

    attribute :active_form, :string do
      allow_nil? true
      public? true
    end

    attribute :blocks, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :blocked_by, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    timestamps()
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :subject,
        :description,
        :status,
        :owner,
        :team_name,
        :active_form,
        :blocks,
        :blocked_by,
        :metadata
      ]
    end

    update :update do
      accept [
        :subject,
        :description,
        :status,
        :owner,
        :team_name,
        :active_form,
        :blocks,
        :blocked_by,
        :metadata
      ]
    end

    read :by_team do
      argument :team_name, :string, allow_nil?: false

      filter expr(team_name == ^arg(:team_name))
    end

    read :by_owner do
      argument :owner, :string, allow_nil?: false

      filter expr(owner == ^arg(:owner))
    end
  end

  identities do
    identity :unique_task, [:id]
  end
end
