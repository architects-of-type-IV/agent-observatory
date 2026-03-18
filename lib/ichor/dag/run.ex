defmodule Ichor.Dag.Run do
  @moduledoc """
  A DAG execution session. One per build attempt.
  Binds a set of Jobs to a project/node and tracks overall lifecycle.
  """

  use Ash.Resource,
    domain: Ichor.Dag,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo(Ichor.Repo)
    table("dag_runs")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :label, :string do
      allow_nil?(false)
      public?(true)
      description("Human name (project title)")
    end

    attribute :source, :atom do
      allow_nil?(false)
      public?(true)
      constraints(one_of: [:genesis, :imported])
      description("Origin: :genesis (from Genesis hierarchy) or :imported (from tasks.jsonl)")
    end

    attribute :node_id, :string do
      public?(true)
      description("Genesis.Node UUID (nullable, genesis runs only)")
    end

    attribute :project_path, :string do
      public?(true)
      description("Filesystem path (nullable, imported runs only)")
    end

    attribute :tmux_session, :string do
      public?(true)
      description("Tmux session name (set by Spawner)")
    end

    attribute :status, :atom do
      allow_nil?(false)
      default(:active)
      public?(true)
      constraints(one_of: [:active, :completed, :failed, :archived])
    end

    attribute :job_count, :integer do
      default(0)
      public?(true)
    end

    timestamps()
  end

  relationships do
    has_many :jobs, Ichor.Dag.Job
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:label, :source, :node_id, :project_path, :tmux_session, :status, :job_count])
    end

    update :complete do
      accept([])
      change(set_attribute(:status, :completed))
    end

    update :fail do
      accept([])
      change(set_attribute(:status, :failed))
    end

    update :archive do
      accept([])
      change(set_attribute(:status, :archived))
    end

    read :active do
      filter(expr(status == :active))
      prepare(build(sort: [inserted_at: :desc]))
    end

    read :by_node do
      argument :node_id, :string do
        allow_nil?(false)
      end

      filter(expr(node_id == ^arg(:node_id) and status == :active))
      prepare(build(sort: [inserted_at: :desc]))
    end

    read :by_path do
      argument :project_path, :string do
        allow_nil?(false)
      end

      filter(expr(project_path == ^arg(:project_path) and status == :active))
      prepare(build(sort: [inserted_at: :desc]))
    end
  end

  code_interface do
    define(:create)
    define(:get, action: :read, get_by: [:id])
    define(:complete)
    define(:fail)
    define(:archive)
    define(:active)
    define(:by_node, args: [:node_id])
    define(:by_path, args: [:project_path])
  end
end
