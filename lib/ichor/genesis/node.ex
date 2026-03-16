defmodule Ichor.Genesis.Node do
  @moduledoc """
  A Genesis Node represents a subsystem project progressing through
  the Monad Method pipeline: discover -> define -> build -> complete.

  Created from an MES Project brief when Mode A is initiated.
  Accumulates ADRs, Features, UseCases, Conversations, Checkpoints,
  and eventually a Phase/Section/Task/Subtask roadmap hierarchy.
  """

  use Ash.Resource,
    domain: Ichor.Genesis,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo(Ichor.Repo)
    table("genesis_nodes")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :description, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :brief, :string do
      public?(true)
      description("Original MES brief content")
    end

    attribute :stakeholders, {:array, :string} do
      public?(true)
      default([])
    end

    attribute :constraints, {:array, :string} do
      public?(true)
      default([])
    end

    attribute :status, :atom do
      allow_nil?(false)
      default(:discover)
      public?(true)
      constraints(one_of: [:discover, :define, :build, :complete])
    end

    attribute :mes_project_id, :uuid do
      public?(true)
      description("Link back to the MES Project that spawned this node")
    end

    timestamps()
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:title, :description, :brief, :stakeholders, :constraints, :mes_project_id])
    end

    update :update do
      primary?(true)
      accept([:title, :description, :brief, :stakeholders, :constraints])
    end

    update :advance do
      accept([])
      require_atomic?(false)

      argument :status, :atom do
        allow_nil?(false)
        constraints(one_of: [:discover, :define, :build, :complete])
      end

      change(fn changeset, _context ->
        status = Ash.Changeset.get_argument(changeset, :status)
        Ash.Changeset.change_attribute(changeset, :status, status)
      end)
    end

    read :list_all do
      prepare(build(sort: [inserted_at: :desc]))
    end

    read :by_status do
      argument :status, :atom do
        allow_nil?(false)
        constraints(one_of: [:discover, :define, :build, :complete])
      end

      filter(expr(status == ^arg(:status)))
      prepare(build(sort: [inserted_at: :desc]))
    end
  end

  code_interface do
    define(:create)
    define(:update)
    define(:get, action: :read, get_by: [:id])
    define(:advance, args: [:status])
    define(:list_all)
    define(:by_status, args: [:status])
  end
end
