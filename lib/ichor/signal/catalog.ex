defmodule Ichor.Signal.Catalog do
  @moduledoc """
  Declarative catalog of every signal in the ICHOR nervous system.
  Source of truth for signal validation, the /signals page, and Archon Watchdog.

  Add new signals here. If it's not in the catalog, `Signal.emit/2` raises.
  """

  @type signal_def :: %{
          category: atom(),
          keys: [atom()],
          dynamic: boolean(),
          doc: String.t()
        }

  # ── Signal Definitions ──────────────────────────────────────────────

  @signals %{
    # ── Fleet ──────────────────────────────────────────────────────
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

    # ── System ─────────────────────────────────────────────────────
    heartbeat: %{category: :system, keys: [:count], doc: "Monotonic counter every 5s"},
    registry_changed: %{category: :system, keys: [], doc: "AgentRegistry ETS modified"},
    dashboard_command: %{
      category: :system,
      keys: [:command],
      doc: "External command to dashboard"
    },

    # ── Events ─────────────────────────────────────────────────────
    new_event: %{category: :events, keys: [:event], doc: "Hook event ingested by EventController"},

    # ── Gateway ────────────────────────────────────────────────────
    decision_log: %{category: :gateway, keys: [:log], doc: "Inter-agent message routed"},
    schema_violation: %{category: :gateway, keys: [:event_map], doc: "Schema validation failure"},
    node_state_update: %{
      category: :gateway,
      keys: [:agent_id, :state],
      doc: "Topology node change"
    },
    entropy_alert: %{
      category: :gateway,
      keys: [:session_id, :entropy_score],
      doc: "Repeated pattern detected"
    },
    topology_snapshot: %{
      category: :gateway,
      keys: [:nodes, :edges],
      doc: "Full topology snapshot"
    },
    capability_update: %{
      category: :gateway,
      keys: [:state_map],
      doc: "Agent capability map changed"
    },
    dead_letter: %{category: :gateway, keys: [:delivery], doc: "Failed webhook to DLQ"},
    gateway_audit: %{
      category: :gateway,
      keys: [:envelope_id, :channel],
      doc: "Message routing audit"
    },
    mesh_pause: %{category: :gateway, keys: [:initiated_by], doc: "God-mode mesh pause"},

    # ── Agent ──────────────────────────────────────────────────────
    agent_crashed: %{
      category: :agent,
      keys: [:session_id, :team_name],
      doc: "Agent confirmed dead"
    },
    nudge_warning: %{
      category: :agent,
      keys: [:session_id, :agent_name, :level],
      doc: "Nudge escalation: warn"
    },
    nudge_sent: %{
      category: :agent,
      keys: [:session_id, :agent_name, :level],
      doc: "Nudge escalation: tmux nudge sent"
    },
    nudge_escalated: %{
      category: :agent,
      keys: [:session_id, :agent_name, :level],
      doc: "Nudge escalation: HITL pause"
    },
    nudge_zombie: %{
      category: :agent,
      keys: [:session_id, :agent_name, :level],
      doc: "Nudge escalation: zombie"
    },
    agent_spawned: %{
      category: :agent,
      keys: [:session_id, :name, :capability],
      doc: "Agent spawned via dashboard"
    },
    agent_event: %{category: :agent, keys: [:event], dynamic: true, doc: "Per-agent event stream"},
    terminal_output: %{
      category: :agent,
      keys: [:session_id, :output],
      dynamic: true,
      doc: "Tmux output"
    },
    mailbox_message: %{
      category: :agent,
      keys: [:message],
      dynamic: true,
      doc: "Direct message to agent"
    },
    agent_instructions: %{
      category: :agent,
      keys: [:agent_class, :instructions],
      dynamic: true,
      doc: "Pushed instructions"
    },
    scheduled_job: %{
      category: :agent,
      keys: [:agent_id, :payload],
      dynamic: true,
      doc: "Cron job fired"
    },

    # ── HITL ───────────────────────────────────────────────────────
    gate_open: %{
      category: :hitl,
      keys: [:session_id],
      dynamic: true,
      doc: "Agent paused, gate opened"
    },
    gate_close: %{
      category: :hitl,
      keys: [:session_id],
      dynamic: true,
      doc: "Agent resumed, gate closed"
    },

    # ── Mesh ───────────────────────────────────────────────────────
    dag_delta: %{
      category: :mesh,
      keys: [:session_id, :added_nodes],
      dynamic: true,
      doc: "Causal DAG update"
    },

    # ── Team ───────────────────────────────────────────────────────
    task_created: %{category: :team, keys: [:task], dynamic: true, doc: "New task added"},
    task_updated: %{category: :team, keys: [:task], dynamic: true, doc: "Task status changed"},
    task_deleted: %{category: :team, keys: [:task_id], dynamic: true, doc: "Task removed"},
    tasks_updated: %{category: :team, keys: [:team_name], doc: "Team task list changed"},

    # ── Monitoring ─────────────────────────────────────────────────
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
    swarm_state: %{category: :monitoring, keys: [:state_map], doc: "Swarm pipeline recomputed"},

    # ── Messages ───────────────────────────────────────────────────
    message_delivered: %{
      category: :messages,
      keys: [:agent_id, :msg_map],
      doc: "Message delivered to agent"
    },

    # ── Memory ─────────────────────────────────────────────────────
    block_changed: %{category: :memory, keys: [:block_id, :label], doc: "Memory block modified"},
    memory_changed: %{
      category: :memory,
      keys: [:agent_name, :event],
      dynamic: true,
      doc: "Per-agent memory change"
    }
  }

  # ── Compile-time derivations ────────────────────────────────────────

  @catalog Map.new(@signals, fn {k, v} -> {k, Map.put_new(v, :dynamic, false)} end)
  @categories @catalog |> Map.values() |> Enum.map(& &1.category) |> Enum.uniq() |> Enum.sort()
  @static_signals @catalog |> Enum.reject(fn {_, v} -> v.dynamic end) |> Enum.map(&elem(&1, 0))

  # ── Public API ──────────────────────────────────────────────────────

  @spec lookup(atom()) :: signal_def() | nil
  def lookup(name), do: Map.get(@catalog, name)

  @spec lookup!(atom()) :: signal_def()
  def lookup!(name) do
    Map.get(@catalog, name) ||
      raise ArgumentError, "unknown signal: #{inspect(name)}. Add it to Signal.Catalog."
  end

  @spec valid_category?(atom()) :: boolean()
  def valid_category?(cat), do: cat in @categories

  @spec categories() :: [atom()]
  def categories, do: @categories

  @spec all() :: %{atom() => signal_def()}
  def all, do: @catalog

  @spec by_category(atom()) :: [{atom(), signal_def()}]
  def by_category(cat), do: Enum.filter(@catalog, fn {_, v} -> v.category == cat end)

  @spec static_signals() :: [atom()]
  def static_signals, do: @static_signals

  @spec dynamic_signals() :: [{atom(), signal_def()}]
  def dynamic_signals, do: Enum.filter(@catalog, fn {_, v} -> v.dynamic end)
end
