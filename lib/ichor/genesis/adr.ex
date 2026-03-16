defmodule Ichor.Genesis.Adr do
  @moduledoc """
  Architecture Decision Record produced during Mode A (Discover).

  Each ADR captures a design decision with its status, rationale,
  and relationships to other ADRs. Belongs to a Genesis Node.
  """

  use Ash.Resource,
    domain: Ichor.Genesis,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo(Ichor.Repo)
    table("genesis_adrs")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :code, :string do
      allow_nil?(false)
      public?(true)
      description("ADR identifier, e.g. ADR-001")
    end

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :status, :atom do
      allow_nil?(false)
      default(:pending)
      public?(true)
      constraints(one_of: [:pending, :proposed, :accepted, :rejected])
    end

    attribute :content, :string do
      public?(true)
      description("Full ADR body text")
    end

    attribute :research_complete, :boolean do
      default(false)
      public?(true)
    end

    attribute :parent_code, :string do
      public?(true)
      description("Code of parent ADR if this is a refinement")
    end

    attribute :related_adr_codes, {:array, :string} do
      public?(true)
      default([])
    end

    attribute :node_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    timestamps()
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :code,
        :title,
        :status,
        :content,
        :research_complete,
        :parent_code,
        :related_adr_codes,
        :node_id
      ])
    end

    update :update do
      primary?(true)
      accept([:title, :status, :content, :research_complete, :parent_code, :related_adr_codes])
    end

    read :list_all do
      prepare(build(sort: [inserted_at: :desc]))
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
    define(:list_all)
    define(:by_node, args: [:node_id])
  end
end
