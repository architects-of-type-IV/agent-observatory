defmodule Ichor.Genesis.Checkpoint do
  @moduledoc """
  Gate checkpoint marking a milestone in the Monad Method pipeline.

  Records readiness assessments at mode transitions (discover->define,
  define->build, build->complete). Belongs to a Genesis Node.
  """

  use Ash.Resource,
    domain: Ichor.Genesis,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo(Ichor.Repo)
    table("genesis_checkpoints")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :mode, :atom do
      allow_nil?(false)
      public?(true)
      constraints(one_of: [:discover, :define, :build])
      description("Mode this checkpoint assesses readiness for")
    end

    attribute :content, :string do
      public?(true)
      description("Gate check report body")
    end

    attribute :summary, :string do
      public?(true)
      description("One-line readiness verdict")
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
      accept([:title, :mode, :content, :summary, :node_id])
    end

    update :update do
      primary?(true)
      accept([:title, :content, :summary])
    end

    read :by_node do
      argument :node_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(node_id == ^arg(:node_id)))
      prepare(build(sort: [inserted_at: :asc]))
    end
  end

  code_interface do
    define(:create)
    define(:update)
    define(:get, action: :read, get_by: [:id])
    define(:by_node, args: [:node_id])
  end
end
