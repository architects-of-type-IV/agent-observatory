defmodule Ichor.Mesh.DecisionLog do
  @moduledoc """
  Universal message envelope transmitted by every agent in the Hypervisor network.

  Implemented as an Ash embedded resource (not a database table). DecisionLog
  instances are received as HTTP payloads, validated in memory, and forwarded over
  PubSub. They are never persisted directly to Postgres.

  Each section (meta, identity, cognition, action, state_delta, control) is stored
  as a plain `:map` field. These are internal transport envelopes; field-level
  validation is not required.

  See ADR-014 and FRD-006 for the full specification.
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :meta, :map, public?: true
    attribute :identity, :map, public?: true
    attribute :cognition, :map, public?: true
    attribute :action, :map, public?: true
    attribute :state_delta, :map, public?: true
    attribute :control, :map, public?: true
  end

  actions do
    create :create do
      accept [:meta, :identity, :cognition, :action, :state_delta, :control]
    end
  end
end
