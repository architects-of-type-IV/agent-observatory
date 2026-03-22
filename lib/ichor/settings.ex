defmodule Ichor.Settings do
  @moduledoc """
  Domain for application-wide settings and configuration.

  Houses per-category settings resources. Currently manages project
  configuration; future categories include operational thresholds,
  integrations, UI preferences, and feature flags.
  """

  use Ash.Domain

  resources do
    resource Ichor.Settings.SettingsProject do
      define(:create_settings_project, action: :create)
      define(:list_settings_projects, action: :read)
      define(:update_settings_project, action: :update)
      define(:destroy_settings_project, action: :destroy)
    end
  end
end
