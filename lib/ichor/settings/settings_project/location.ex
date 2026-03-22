defmodule Ichor.Settings.SettingsProject.Location do
  @moduledoc """
  Embedded resource for project location configuration.

  Local projects need only a path. Remote projects additionally require
  host, port, username, and authentication method.
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :type, Ichor.Settings.Types.LocationType do
      allow_nil?(false)
      public?(true)
    end

    attribute :path, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute(:host, :string, public?: true)
    attribute(:port, :integer, default: 22, public?: true)
    attribute(:username, :string, public?: true)
    attribute(:auth_method, Ichor.Settings.Types.AuthMethodType, public?: true)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end
end
