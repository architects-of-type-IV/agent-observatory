defmodule Ichor.Projects.Node do
  @moduledoc """
  A Genesis Node represents a subsystem project progressing through
  the Monad Method pipeline: discover -> define -> build -> complete.

  Created from an MES Project brief when Mode A is initiated.
  Accumulates Artifacts (ADRs, Features, UseCases, Checkpoints, Conversations)
  and eventually a RoadmapItem hierarchy (phases, sections, tasks, subtasks).
  """

  use Ash.Resource,
    domain: Ichor.Projects,
    data_layer: AshSqlite.DataLayer,
    simple_notifiers: [Ichor.Signals.FromAsh]

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
      constraints(one_of: [:discover, :define, :build, :complete])
      default(:discover)
      public?(true)
    end

    timestamps()
  end

  relationships do
    belongs_to :mes_project, Ichor.Projects.Project do
      attribute_public?(true)
      allow_nil?(true)
    end

    has_many :artifacts, Ichor.Projects.Artifact
    has_many :roadmap_items, Ichor.Projects.RoadmapItem
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

      argument :status, :atom do
        allow_nil?(false)
        constraints(one_of: [:discover, :define, :build, :complete])
      end

      change(set_attribute(:status, arg(:status)))
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

    read :by_project do
      argument :mes_project_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(mes_project_id == ^arg(:mes_project_id)))
    end
  end

  code_interface do
    define(:create)
    define(:update)
    define(:get, action: :read, get_by: [:id])
    define(:advance, args: [:status])
    define(:list_all)
    define(:by_status, args: [:status])
    define(:by_project, args: [:mes_project_id])
  end
end
