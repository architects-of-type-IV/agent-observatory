defmodule Ichor.Mes.Project do
  @moduledoc """
  A subsystem project brief produced by an MES agent team.

  Lifecycle: proposed -> in_progress -> compiled -> loaded (or failed at any stage).
  Once loaded, the subsystem's BEAM modules are live in the running VM.
  """

  use Ash.Resource,
    domain: Ichor.Mes,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo(Ichor.Repo)
    table("mes_projects")
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

    attribute :subsystem, :string do
      allow_nil?(false)
      public?(true)
      description("Technical module/component name")
    end

    attribute :signal_interface, :string do
      allow_nil?(false)
      public?(true)
      description("How this subsystem is controlled through Signals")
    end

    attribute :topic, :string do
      public?(true)
      description("Unique PubSub topic (e.g. subsystem:correlator)")
    end

    attribute :version, :string do
      public?(true)
      default("0.1.0")
      description("SemVer version string")
    end

    attribute :features, {:array, :string} do
      public?(true)
      default([])
      description("List of capability descriptions")
    end

    attribute :use_cases, {:array, :string} do
      public?(true)
      default([])
      description("Concrete scenarios where this subsystem is useful")
    end

    attribute :architecture, :string do
      public?(true)
      description("Internal structure: processes, ETS tables, supervision")
    end

    attribute :dependencies, {:array, :string} do
      public?(true)
      default([])
      description("Ichor modules this subsystem requires")
    end

    attribute :signals_emitted, {:array, :string} do
      public?(true)
      default([])
      description("Signal atoms this subsystem emits")
    end

    attribute :signals_subscribed, {:array, :string} do
      public?(true)
      default([])
      description("Signal atoms or categories this subsystem subscribes to")
    end

    attribute :status, :atom do
      allow_nil?(false)
      default(:proposed)
      public?(true)
      constraints(one_of: [:proposed, :in_progress, :compiled, :loaded, :failed])
    end

    attribute :team_name, :string do
      public?(true)
      description("MES team that produced this brief")
    end

    attribute :run_id, :string do
      public?(true)
      description("Scheduler run UUID grouping agents from same cycle")
    end

    attribute :picked_up_by, :string do
      public?(true)
      description("Agent session that claimed this for implementation")
    end

    attribute :picked_up_at, :utc_datetime_usec do
      public?(true)
    end

    attribute :path, :string do
      public?(true)
      description("Filesystem path to the built Mix project in subsystems/")
    end

    attribute :build_log, :string do
      public?(true)
      description("Last build output or error message")
    end

    timestamps()
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :title,
        :description,
        :subsystem,
        :signal_interface,
        :topic,
        :version,
        :features,
        :use_cases,
        :architecture,
        :dependencies,
        :signals_emitted,
        :signals_subscribed,
        :team_name,
        :run_id
      ])
    end

    update :update do
      primary?(true)
      accept([:status, :path, :build_log])
    end

    update :pick_up do
      accept([])
      require_atomic?(false)

      argument :session_id, :string do
        allow_nil?(false)
      end

      change(set_attribute(:status, :in_progress))
      change(set_attribute(:picked_up_at, &DateTime.utc_now/0))

      change(fn changeset, _context ->
        session_id = Ash.Changeset.get_argument(changeset, :session_id)
        Ash.Changeset.change_attribute(changeset, :picked_up_by, session_id)
      end)
    end

    update :mark_compiled do
      accept([])
      require_atomic?(false)

      argument :path, :string do
        allow_nil?(false)
      end

      change(set_attribute(:status, :compiled))

      change(fn changeset, _context ->
        path = Ash.Changeset.get_argument(changeset, :path)
        Ash.Changeset.change_attribute(changeset, :path, path)
      end)
    end

    update :mark_loaded do
      accept([])
      change(set_attribute(:status, :loaded))
    end

    update :mark_failed do
      accept([])
      require_atomic?(false)

      argument :build_log, :string do
        allow_nil?(false)
      end

      change(set_attribute(:status, :failed))

      change(fn changeset, _context ->
        log = Ash.Changeset.get_argument(changeset, :build_log)
        Ash.Changeset.change_attribute(changeset, :build_log, log)
      end)
    end

    read :list_all do
      prepare(build(sort: [inserted_at: :desc]))
    end

    read :by_status do
      argument :status, :atom do
        allow_nil?(false)
        constraints(one_of: [:proposed, :in_progress, :compiled, :loaded, :failed])
      end

      filter(expr(status == ^arg(:status)))
      prepare(build(sort: [inserted_at: :desc]))
    end
  end

  code_interface do
    define(:create)
    define(:update)
    define(:get, action: :read, get_by: [:id])
    define(:pick_up, args: [:session_id])
    define(:mark_compiled, args: [:path])
    define(:mark_loaded)
    define(:mark_failed, args: [:build_log])
    define(:list_all)
    define(:by_status, args: [:status])
  end
end
