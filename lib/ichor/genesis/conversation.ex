defmodule Ichor.Genesis.Conversation do
  @moduledoc """
  Design conversation log from a Monad Method mode session.

  Records the key decisions, debates, and rationale from agent
  teams working on a mode. Belongs to a Genesis Node.
  """

  use Ash.Resource,
    domain: Ichor.Projects,
    data_layer: AshSqlite.DataLayer,
    simple_notifiers: [Ichor.Signals.FromAsh]

  sqlite do
    repo(Ichor.Repo)
    table("genesis_conversations")
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
    end

    attribute :content, :string do
      public?(true)
      description("Full conversation transcript or summary")
    end

    attribute :participants, {:array, :string} do
      public?(true)
      default([])
      description("Agent session IDs that participated")
    end

    timestamps()
  end

  relationships do
    belongs_to :node, Ichor.Genesis.Node do
      allow_nil?(false)
      attribute_public?(true)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:title, :mode, :content, :participants, :node_id])
    end

    update :update do
      primary?(true)
      accept([:title, :content, :participants])
    end

    read :by_node do
      argument :node_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(node_id == ^arg(:node_id)))
      prepare(build(sort: [inserted_at: :desc]))
    end
  end

  code_interface do
    define(:create)
    define(:update)
    define(:get, action: :read, get_by: [:id])
    define(:by_node, args: [:node_id])
  end
end
