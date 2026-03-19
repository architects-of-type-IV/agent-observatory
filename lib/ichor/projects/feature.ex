defmodule Ichor.Projects.Feature do
  @moduledoc """
  Feature Requirements Document produced during Mode B (Define).

  Each Feature maps to one or more ADRs and contains inline
  Functional Requirements. Belongs to a Genesis Node.
  """

  use Ash.Resource,
    domain: Ichor.Projects,
    data_layer: AshSqlite.DataLayer,
    simple_notifiers: [Ichor.Signals.FromAsh]

  sqlite do
    repo(Ichor.Repo)
    table("genesis_features")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :code, :string do
      allow_nil?(false)
      public?(true)
      description("Feature identifier, e.g. FRD-001")
    end

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :content, :string do
      public?(true)
      description("Full FRD body with inline FRs")
    end

    attribute :adr_codes, {:array, :string} do
      public?(true)
      default([])
      description("ADR codes this feature implements")
    end

    timestamps()
  end

  relationships do
    belongs_to :node, Ichor.Projects.Node do
      allow_nil?(false)
      attribute_public?(true)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:code, :title, :content, :adr_codes, :node_id])
    end

    update :update do
      primary?(true)
      accept([:title, :content, :adr_codes])
    end

    read :by_node do
      argument :node_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(node_id == ^arg(:node_id)))
      prepare(build(sort: [code: :asc]))
    end
  end

  code_interface do
    define(:create)
    define(:update)
    define(:get, action: :read, get_by: [:id])
    define(:by_node, args: [:node_id])
  end
end
