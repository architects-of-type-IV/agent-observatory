defmodule Ichor.Signals.Catalog do
  @moduledoc """
  Declarative catalog of every signal in the ICHOR nervous system.
  Source of truth for signal validation, the /signals page, and Archon Watchdog.

  Add new signals here. If it's not in the catalog, `Signals.emit/2` raises.
  """

  @type signal_def :: %{
          category: atom(),
          keys: [atom()],
          dynamic: boolean(),
          doc: String.t()
        }

  alias Ichor.Signals.Catalog.GatewayAgentDefs
  alias Ichor.Signals.Catalog.GenesisDagDefs
  alias Ichor.Signals.Catalog.MesDefs

  @core_defs %{
    agent_started: %{
      category: :fleet,
      keys: [:session_id, :role, :team],
      doc: "AgentProcess init"
    },
    agent_paused: %{category: :fleet, keys: [:session_id], doc: "Agent paused via HITL"},
    agent_resumed: %{category: :fleet, keys: [:session_id], doc: "Agent resumed"},
    agent_stopped: %{
      category: :fleet,
      keys: [:session_id, :reason],
      doc: "AgentProcess terminated"
    },
    team_created: %{category: :fleet, keys: [:name, :project, :strategy], doc: "New team started"},
    team_disbanded: %{category: :fleet, keys: [:team_name], doc: "Team removed"},
    hosts_changed: %{category: :fleet, keys: [], doc: "Cluster node joined/departed"},
    fleet_changed: %{category: :fleet, keys: [:agent_id], doc: "Agent Registry metadata changed"},
    heartbeat: %{category: :system, keys: [:count], doc: "Monotonic counter every 5s"},
    registry_changed: %{category: :system, keys: [], doc: "Agent registry modified"},
    dashboard_command: %{
      category: :system,
      keys: [:command],
      doc: "External command to dashboard"
    },
    new_event: %{category: :events, keys: [:event], doc: "Hook event ingested by EventController"},
    message_delivered: %{
      category: :messages,
      keys: [:agent_id, :msg_map],
      doc: "Message delivered to agent"
    },
    block_changed: %{category: :memory, keys: [:block_id, :label], doc: "Memory block modified"},
    memory_changed: %{
      category: :memory,
      keys: [:agent_name, :event],
      dynamic: true,
      doc: "Per-agent memory change"
    },
    agent_evicted: %{
      category: :fleet,
      keys: [:session_id],
      doc: "Agent evicted due to missed heartbeats"
    },
    agent_reaped: %{
      category: :fleet,
      keys: [:session_id],
      doc: "Dead agent reaped by TmuxDiscovery"
    },
    agent_discovered: %{
      category: :fleet,
      keys: [:session_id],
      doc: "Agent discovered via tmux session scan"
    }
  }

  @team_monitoring_defs %{
    task_created: %{category: :team, keys: [:task], dynamic: true, doc: "New task added"},
    task_updated: %{category: :team, keys: [:task], dynamic: true, doc: "Task status changed"},
    task_deleted: %{category: :team, keys: [:task_id], dynamic: true, doc: "Task removed"},
    tasks_updated: %{category: :team, keys: [:team_name], doc: "Team task list changed"},
    protocol_update: %{
      category: :monitoring,
      keys: [:stats_map],
      doc: "Protocol stats recomputed"
    },
    gate_passed: %{
      category: :monitoring,
      keys: [:session_id, :task_id],
      doc: "Quality gate passed"
    },
    gate_failed: %{
      category: :monitoring,
      keys: [:session_id, :task_id, :output],
      doc: "Quality gate failed"
    },
    agent_done: %{
      category: :monitoring,
      keys: [:session_id, :summary],
      doc: "Agent signalled DONE"
    },
    agent_blocked: %{
      category: :monitoring,
      keys: [:session_id, :reason],
      doc: "Agent signalled BLOCKED"
    },
    watchdog_sweep: %{
      category: :monitoring,
      keys: [:orphaned_count],
      doc: "TeamWatchdog periodic sweep completed"
    }
  }

  @signals @core_defs
           |> Map.merge(GatewayAgentDefs.definitions())
           |> Map.merge(@team_monitoring_defs)
           |> Map.merge(MesDefs.definitions())
           |> Map.merge(GenesisDagDefs.definitions())

  @catalog Map.new(@signals, fn {k, v} -> {k, Map.put_new(v, :dynamic, false)} end)
  @categories @catalog |> Map.values() |> Enum.map(& &1.category) |> Enum.uniq() |> Enum.sort()
  @static_signals @catalog |> Enum.reject(fn {_, v} -> v.dynamic end) |> Enum.map(&elem(&1, 0))

  @doc "Look up a signal definition by name. Returns nil if not found."
  @spec lookup(atom()) :: signal_def() | nil
  def lookup(name), do: Map.get(@catalog, name)

  @doc "Look up a signal definition, deriving one from name prefix if absent."
  @spec lookup!(atom()) :: signal_def()
  def lookup!(name) do
    Map.get(@catalog, name) || derive(name)
  end

  @doc "Derive a signal definition from its name prefix. Allows signals to work without catalog entries."
  @spec derive(atom()) :: signal_def()
  def derive(name) do
    category =
      name
      |> Atom.to_string()
      |> String.split("_", parts: 2)
      |> hd()
      |> String.to_existing_atom()

    %{category: category, keys: [], dynamic: false, doc: "auto-derived"}
  rescue
    ArgumentError -> %{category: :uncategorized, keys: [], dynamic: false, doc: "auto-derived"}
  end

  @doc "True if the given atom is a known signal category."
  @spec valid_category?(atom()) :: boolean()
  def valid_category?(cat), do: cat in @categories

  @doc "Return the list of all known signal categories."
  @spec categories() :: [atom()]
  def categories, do: @categories

  @doc "Return the full signal catalog map."
  @spec all() :: %{atom() => signal_def()}
  def all, do: @catalog

  @doc "Return all signal definitions for a given category."
  @spec by_category(atom()) :: [{atom(), signal_def()}]
  def by_category(cat), do: Enum.filter(@catalog, fn {_, v} -> v.category == cat end)

  @doc "Return all non-dynamic signal names."
  @spec static_signals() :: [atom()]
  def static_signals, do: @static_signals

  @doc "Return all dynamic signal definitions."
  @spec dynamic_signals() :: [{atom(), signal_def()}]
  def dynamic_signals, do: Enum.filter(@catalog, fn {_, v} -> v.dynamic end)
end
