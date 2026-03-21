defmodule Ichor.Workshop.SpawnLink do
  @moduledoc false
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute(:from, :integer, allow_nil?: false, public?: true)
    attribute(:to, :integer, allow_nil?: false, public?: true)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end
end
