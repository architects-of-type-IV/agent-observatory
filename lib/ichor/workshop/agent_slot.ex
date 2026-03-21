defmodule Ichor.Workshop.AgentSlot do
  @moduledoc false
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute(:id, :integer, allow_nil?: false, public?: true)
    attribute(:agent_type_id, :string, public?: true)
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:capability, :string, allow_nil?: false, default: "builder", public?: true)
    attribute(:model, :string, allow_nil?: false, default: "sonnet", public?: true)
    attribute(:permission, :string, allow_nil?: false, default: "default", public?: true)
    attribute(:persona, :string, default: "", public?: true)
    attribute(:file_scope, :string, default: "", public?: true)
    attribute(:quality_gates, :string, default: "", public?: true)
    attribute(:tools, {:array, :string}, default: [], public?: true)
    attribute(:x, :integer, allow_nil?: false, public?: true)
    attribute(:y, :integer, allow_nil?: false, public?: true)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end
end
