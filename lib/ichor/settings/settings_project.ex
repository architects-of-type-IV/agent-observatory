defmodule Ichor.Settings.SettingsProject do
  @moduledoc """
  A managed project with name, active status, and location configuration.

  Projects can be local filesystem folders or remote SSH-accessible directories.
  """

  use Ash.Resource,
    domain: Ichor.Settings,
    data_layer: AshSqlite.DataLayer,
    simple_notifiers: [Ichor.Signals.FromAsh]

  sqlite do
    repo(Ichor.Repo)
    table("settings_projects")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :is_active, :boolean do
      default(true)
      public?(true)
    end

    attribute :location, Ichor.Settings.SettingsProject.Location do
      allow_nil?(false)
      public?(true)
    end

    attribute(:repo_name, :string, public?: true)
    attribute(:repo_url, :string, public?: true)

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept(:*)
      change(Ichor.Settings.SettingsProject.GitInfo)
    end

    update :update do
      accept(:*)
      change(Ichor.Settings.SettingsProject.GitInfo)
    end
  end
end
