defmodule Ichor.Factory.Artifact do
  @moduledoc """
  Unified Genesis artifact produced during the Monad Method pipeline.

  Consolidates ADR, Feature, UseCase, Checkpoint, and Conversation into a
  single resource discriminated by `kind`. Belongs to a Genesis Node.

  Kind-specific fields:
  - :adr        -- code, title, status, content, research_complete, parent_code, related_adr_codes
  - :feature    -- code, title, content, adr_codes
  - :use_case   -- code, title, content, feature_code
  - :checkpoint -- title, mode, content, summary
  - :conversation -- title, mode, content, participants
  """

  use Ash.Resource,
    domain: Ichor.Factory,
    data_layer: AshSqlite.DataLayer,
    simple_notifiers: [Ichor.Signals.FromAsh]

  sqlite do
    repo(Ichor.Repo)
    table("genesis_artifacts")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :kind, :atom do
      allow_nil?(false)
      public?(true)
      constraints(one_of: [:adr, :feature, :use_case, :checkpoint, :conversation])
      description("Artifact type discriminator")
    end

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    # Shared optional text body
    attribute :content, :string do
      public?(true)
      description("Full artifact body text")
    end

    # ADR / Feature / UseCase: structured code identifier
    attribute :code, :string do
      public?(true)
      description("Artifact identifier, e.g. ADR-001, FRD-001, UC-0001")
    end

    # ADR: lifecycle status
    attribute :status, :atom do
      public?(true)
      constraints(one_of: [:pending, :proposed, :accepted, :rejected])
      default(:pending)
      description("ADR lifecycle status (only meaningful for :adr kind)")
    end

    # ADR: research flag
    attribute :research_complete, :boolean do
      public?(true)
      default(false)
    end

    # ADR: parent reference
    attribute :parent_code, :string do
      public?(true)
      description("Code of parent ADR if this is a refinement")
    end

    # ADR: related ADR cross-references
    attribute :related_adr_codes, {:array, :string} do
      public?(true)
      default([])
    end

    # Feature: ADR codes this feature implements
    attribute :adr_codes, {:array, :string} do
      public?(true)
      default([])
      description("ADR codes this feature implements (only meaningful for :feature kind)")
    end

    # UseCase: parent feature reference
    attribute :feature_code, :string do
      public?(true)
      description("Feature code this UC validates (only meaningful for :use_case kind)")
    end

    # Checkpoint / Conversation: pipeline mode
    attribute :mode, :atom do
      public?(true)
      constraints(one_of: [:discover, :define, :build, :gate_a, :gate_b, :gate_c])
      description("Pipeline mode (only meaningful for :checkpoint and :conversation kinds)")
    end

    # Checkpoint: one-line readiness verdict
    attribute :summary, :string do
      public?(true)
      description("One-line readiness verdict (only meaningful for :checkpoint kind)")
    end

    # Conversation: participating agent session IDs
    attribute :participants, {:array, :string} do
      public?(true)
      default([])
      description("Agent session IDs that participated (only meaningful for :conversation kind)")
    end

    timestamps()
  end

  relationships do
    belongs_to :node, Ichor.Factory.Node do
      allow_nil?(false)
      attribute_public?(true)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :kind,
        :title,
        :content,
        :code,
        :status,
        :research_complete,
        :parent_code,
        :related_adr_codes,
        :adr_codes,
        :feature_code,
        :mode,
        :summary,
        :participants,
        :node_id
      ])
    end

    update :update do
      primary?(true)

      accept([
        :title,
        :content,
        :code,
        :status,
        :research_complete,
        :parent_code,
        :related_adr_codes,
        :adr_codes,
        :feature_code,
        :mode,
        :summary,
        :participants
      ])
    end

    read :list_all do
      prepare(build(sort: [inserted_at: :desc]))
    end

    read :by_node do
      argument :node_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(node_id == ^arg(:node_id)))
      prepare(build(sort: [inserted_at: :asc]))
    end

    read :by_node_and_kind do
      argument :node_id, :uuid do
        allow_nil?(false)
      end

      argument :kind, :atom do
        allow_nil?(false)
        constraints(one_of: [:adr, :feature, :use_case, :checkpoint, :conversation])
      end

      filter(expr(node_id == ^arg(:node_id) and kind == ^arg(:kind)))
      prepare(build(sort: [code: :asc, inserted_at: :asc]))
    end
  end

  code_interface do
    define(:create)
    define(:update)
    define(:get, action: :read, get_by: [:id])
    define(:list_all)
    define(:by_node, args: [:node_id])
    define(:by_node_and_kind, args: [:node_id, :kind])
  end
end
