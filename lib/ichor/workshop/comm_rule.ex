defmodule Ichor.Workshop.CommRule do
  @moduledoc false
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute(:from, :integer, allow_nil?: false, public?: true)
    attribute(:to, :integer, allow_nil?: false, public?: true)
    attribute(:policy, :string, allow_nil?: false, default: "allow", public?: true)
    attribute(:via, :integer, public?: true)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end
end
