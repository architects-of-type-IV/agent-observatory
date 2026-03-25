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

  @core_defs %{
    agent_started: %{
      category: :fleet,
      keys: [:session_id, :name, :role, :team],
      doc: "AgentProcess init"
    },
    agent_paused: %{category: :fleet, keys: [:session_id, :name], doc: "Agent paused via HITL"},
    agent_resumed: %{category: :fleet, keys: [:session_id, :name], doc: "Agent resumed"},
    agent_stopped: %{
      category: :fleet,
      keys: [:session_id, :name, :reason],
      doc: "AgentProcess terminated"
    },
    team_created: %{category: :fleet, keys: [:name, :project, :strategy], doc: "New team started"},
    team_disbanded: %{category: :fleet, keys: [:team_name], doc: "Team removed"},
    team_spawn_requested: %{
      category: :fleet,
      keys: [:team_name, :spec, :source],
      dynamic: true,
      doc: "Team spawn requested; runtime should create tmux session and windows"
    },
    team_spawn_started: %{
      category: :fleet,
      keys: [:team_name, :agent_count, :source],
      dynamic: true,
      doc: "Spawn request accepted by runtime launch handler"
    },
    team_spawn_ready: %{
      category: :fleet,
      keys: [:session, :team_name, :agent_count, :source],
      dynamic: true,
      doc: "Requested team spawn completed successfully"
    },
    team_spawn_failed: %{
      category: :fleet,
      keys: [:team_name, :reason, :source],
      dynamic: true,
      doc: "Requested team spawn failed"
    },
    run_complete: %{
      category: :fleet,
      keys: [:kind, :run_id, :session],
      doc: "Run completed cleanly (any kind: mes, planning, pipeline)"
    },
    run_terminated: %{
      category: :fleet,
      keys: [:kind, :run_id, :session],
      doc: "Run process terminated (any kind: mes, planning, pipeline)"
    },
    hosts_changed: %{category: :fleet, keys: [], doc: "Cluster node joined/departed"},
    # NOTE: :agent_id key here is intentionally named differently from :session_id used in
    # agent lifecycle signals (:agent_started, :agent_stopped, etc.). In agent lifecycle signals
    # :session_id is the canonical process identifier. Here :agent_id is the ETS registry key
    # that changed. No current consumers read this key (both dashboard_info_handlers and the
    # signal renderer react to the signal name only), so renaming would be safe but low-value.
    # Tracked as AD-7. If a consumer ever needs to read this field, standardise to :session_id.
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
    },
    session_started: %{
      category: :fleet,
      keys: [:session_id, :tmux_session, :cwd, :model, :os_pid],
      doc: "New agent session started; Infrastructure subscriber spawns AgentProcess"
    },
    session_ended: %{
      category: :fleet,
      keys: [:session_id, :status],
      doc: "Agent session ended; Infrastructure subscriber terminates AgentProcess"
    },
    team_create_requested: %{
      category: :fleet,
      keys: [:team_name],
      doc: "TeamCreate tool intercepted; Infrastructure subscriber creates TeamSupervisor"
    },
    team_delete_requested: %{
      category: :fleet,
      keys: [:team_name],
      doc: "TeamDelete tool intercepted; Infrastructure subscriber disbands team"
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

  @gateway_agent_defs %{
    schema_violation: %{
      category: :gateway,
      keys: [:event_map],
      doc: "Schema validation failure"
    },
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
    webhook_delivery_enqueued: %{
      category: :gateway,
      keys: [:delivery_id, :agent_id, :target_url, :status, :attempt_count],
      doc: "Webhook delivery job enqueued into Oban"
    },
    webhook_delivery_delivered: %{
      category: :gateway,
      keys: [:delivery_id, :agent_id, :target_url, :status, :attempt_count],
      doc: "Webhook delivery confirmed delivered by worker"
    },
    gateway_audit: %{
      category: :gateway,
      keys: [:envelope_id, :channel],
      doc: "Message routing audit"
    },
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
    agent_event: %{
      category: :agent,
      keys: [:event],
      dynamic: true,
      doc: "Per-agent event stream"
    },
    agent_message_intercepted: %{
      category: :agent,
      keys: [:from, :to, :content, :type],
      dynamic: true,
      doc: "Hook-intercepted SendMessage (signal only, no delivery)"
    },
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
    cron_job_scheduled: %{
      category: :gateway,
      keys: [:job_id, :agent_id, :next_fire_at],
      doc: "Cron job created via Ash action"
    },
    cron_job_rescheduled: %{
      category: :gateway,
      keys: [:job_id, :agent_id, :next_fire_at],
      doc: "Cron job rescheduled via Ash action"
    },
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
    hitl_auto_released: %{
      category: :hitl,
      keys: [:session_id],
      doc: "Paused session auto-released by sweep"
    },
    hitl_operator_approved: %{
      category: :hitl,
      keys: [:session_id],
      doc: "Operator approved buffered messages"
    },
    hitl_operator_rejected: %{
      category: :hitl,
      keys: [:session_id],
      doc: "Operator rejected buffered messages"
    },
    hitl_intervention_recorded: %{
      category: :hitl,
      keys: [:event_id, :session_id, :agent_id, :operator_id, :action, :details],
      doc: "HITL operator intervention event persisted"
    }
  }

  @mes_defs %{
    mes_scheduler_init: %{
      category: :mes,
      keys: [:paused],
      doc: "MES scheduler initialized and existing runs reconciled"
    },
    mes_scheduler_paused: %{
      category: :mes,
      keys: [:tick],
      doc: "MES scheduler paused — no new teams will spawn"
    },
    mes_scheduler_resumed: %{
      category: :mes,
      keys: [:tick],
      doc: "MES scheduler resumed — team spawning re-enabled"
    },
    mes_tick: %{category: :mes, keys: [:tick, :active_runs], doc: "MES scheduler tick fired"},
    mes_cycle_started: %{
      category: :mes,
      keys: [:run_id, :team_name],
      doc: "MES scheduler spawned a new manufacturing team"
    },
    mes_cycle_skipped: %{
      category: :mes,
      keys: [:tick, :active_runs],
      doc: "MES scheduler skipped tick due to max concurrent runs"
    },
    mes_cycle_failed: %{
      category: :mes,
      keys: [:run_id, :reason],
      doc: "MES run failed to start"
    },
    mes_cycle_timeout: %{
      category: :mes,
      keys: [:run_id, :team_name],
      doc: "MES team run exceeded 10-minute budget and was killed"
    },
    mes_run_init: %{
      category: :mes,
      keys: [:run_id, :team_name],
      doc: "MES RunProcess GenServer initializing"
    },
    mes_run_started: %{
      category: :mes,
      keys: [:run_id, :session],
      doc: "MES RunProcess team spawned and kill timer armed"
    },
    mes_run_terminated: %{
      category: :mes,
      keys: [:run_id],
      doc: "MES RunProcess cleaned up on termination"
    },
    mes_maintenance_init: %{
      category: :mes,
      keys: [:monitored],
      doc: "MES maintenance sweep initialized and monitoring active runs"
    },
    mes_maintenance_cleaned: %{
      category: :mes,
      keys: [:run_id, :trigger],
      doc: "MES maintenance cleaned up resources for a completed or dead run"
    },
    mes_maintenance_error: %{
      category: :mes,
      keys: [:run_id, :reason],
      doc: "MES maintenance encountered an error during cleanup"
    },
    mes_maintenance_skipped: %{
      category: :mes,
      keys: [:run_id, :reason],
      doc: "MES maintenance skipped cleanup because runtime resources are still alive"
    },
    mes_prompts_written: %{
      category: :mes,
      keys: [:run_id, :agent_count],
      doc: "MES agent prompt and script files written to disk"
    },
    mes_tmux_spawning: %{
      category: :mes,
      keys: [:session, :agent_name, :command, :tmux_args],
      doc: "MES about to create tmux session"
    },
    mes_tmux_session_created: %{
      category: :mes,
      keys: [:session, :agent_name],
      doc: "MES tmux session created with first agent window"
    },
    mes_tmux_spawn_failed: %{
      category: :mes,
      keys: [:session, :output, :exit_code],
      doc: "MES tmux session creation failed"
    },
    mes_tmux_window_created: %{
      category: :mes,
      keys: [:session, :agent_name],
      doc: "MES tmux window created for agent"
    },
    mes_team_ready: %{
      category: :mes,
      keys: [:session, :agent_count],
      doc: "All agents spawned in tmux session"
    },
    mes_team_killed: %{category: :mes, keys: [:session], doc: "MES tmux session killed"},
    mes_agent_registered: %{
      category: :mes,
      keys: [:agent_name, :session],
      doc: "MES agent registered in BEAM fleet"
    },
    mes_agent_register_failed: %{
      category: :mes,
      keys: [:agent_name, :reason],
      doc: "MES agent BEAM registration failed"
    },
    mes_team_spawn_failed: %{
      category: :mes,
      keys: [:session, :reason],
      doc: "MES team creation failed"
    },
    mes_operator_ensured: %{
      category: :mes,
      keys: [:status],
      doc: "MES operator AgentProcess verified or created"
    },
    mes_cleanup: %{
      category: :mes,
      keys: [:target],
      doc: "MES cleanup of old prompt dirs or sessions"
    },
    mes_project_created: %{
      category: :mes,
      keys: [:project_id, :title, :run_id],
      doc: "Coordinator submitted a completed brief artifact"
    },
    mes_project_picked_up: %{
      category: :mes,
      keys: [:project_id, :session_id],
      doc: "An implementation team claimed a MES project"
    },
    mes_plugin_loaded: %{
      category: :mes,
      keys: [:project_id, :plugin, :modules],
      doc: "Compiled plugin hot-loaded into BEAM"
    },
    mes_quality_gate_passed: %{
      category: :mes,
      keys: [:run_id, :gate, :session_id],
      doc: "MES quality gate check passed"
    },
    mes_quality_gate_failed: %{
      category: :mes,
      keys: [:run_id, :gate, :session_id, :reason],
      doc: "MES quality gate check failed"
    },
    mes_quality_gate_escalated: %{
      category: :mes,
      keys: [:run_id, :gate, :failure_count],
      doc: "MES quality gate escalated after repeated failures"
    },
    mes_agent_stopped: %{
      category: :mes,
      keys: [:agent_id, :role, :team, :reason],
      doc: "MES agent process stopped (tmux window died or explicit stop)"
    },
    agent_tmux_gone: %{
      category: :fleet,
      keys: [:agent_id, :name, :tmux],
      doc: "Agent's tmux window no longer exists (normal lifecycle event)"
    },
    mes_research_ingested: %{
      category: :mes,
      keys: [:run_id, :project_id, :episode_id],
      doc: "Research brief ingested into the knowledge graph"
    },
    mes_research_ingest_failed: %{
      category: :mes,
      keys: [:run_id, :reason],
      doc: "Research brief ingest to knowledge graph failed"
    },
    mes_project_compiled: %{
      category: :mes,
      keys: [:project_id, :title],
      doc: "MES project marked as compiled"
    },
    mes_project_failed: %{
      category: :mes,
      keys: [:project_id, :title],
      doc: "MES project marked as failed"
    },
    mes_plugin_compile_failed: %{
      category: :mes,
      keys: [:run_id, :project_id, :reason],
      doc: "Plugin compile/load failed after DAG completion"
    },
    mes_output_unhandled: %{
      category: :mes,
      keys: [:run_id, :project_id, :output_kind],
      doc: "Pipeline completed for a project kind with no registered output handler"
    },
    mes_pipeline_generated: %{
      category: :mes,
      keys: [:project_id],
      doc: "Pipeline tasks.jsonl generated for MES project"
    },
    mes_pipeline_launched: %{
      category: :mes,
      keys: [:project_id, :session],
      doc: "Pipeline build team launched for MES project"
    },
    mes_corrective_agent_spawned: %{
      category: :mes,
      keys: [:run_id, :session, :attempt],
      doc: "Corrective agent spawned into existing MES session after coordinator failure"
    },
    mes_corrective_agent_failed: %{
      category: :mes,
      keys: [:run_id, :session, :reason],
      doc: "Corrective agent spawn into existing MES session failed"
    }
  }

  @planning_pipeline_defs %{
    planning_team_ready: %{
      category: :planning,
      keys: [:session, :mode, :project_id, :agent_count],
      doc: "Planning mode team spawned and ready in tmux"
    },
    planning_team_spawn_failed: %{
      category: :planning,
      keys: [:session, :reason],
      doc: "Planning mode team failed to spawn"
    },
    planning_team_killed: %{
      category: :planning,
      keys: [:session],
      doc: "Planning tmux session killed during cleanup"
    },
    planning_run_init: %{
      category: :planning,
      keys: [:run_id, :mode, :session],
      doc: "RunProcess started monitoring a planning mode run"
    },
    planning_tmux_gone: %{
      category: :planning,
      keys: [:run_id, :session],
      doc: "Planning tmux session no longer exists (liveness check)"
    },
    planning_run_complete: %{
      category: :planning,
      keys: [:run_id, :mode, :session, :delivered_by],
      doc: "Planning mode run completed (coordinator delivered to operator)"
    },
    planning_run_terminated: %{
      category: :planning,
      keys: [:run_id, :mode],
      doc: "RunProcess GenServer terminated"
    },
    project_created: %{
      category: :planning,
      keys: [:id, :project_id, :title, :type],
      doc: "Project created"
    },
    project_advanced: %{
      category: :planning,
      keys: [:id, :project_id, :title, :type],
      doc: "Project advanced to next pipeline stage"
    },
    project_artifact_created: %{
      category: :planning,
      keys: [:project_id],
      doc: "Project artifact added; consumers query the project for specifics"
    },
    project_roadmap_item_created: %{
      category: :planning,
      keys: [:project_id],
      doc: "Project roadmap item added; consumers query the project for specifics"
    },
    pipeline_created: %{
      category: :pipeline,
      keys: [:run_id, :source, :label, :task_count],
      doc: "Pipeline created (project-derived or imported ingest)"
    },
    pipeline_ready: %{
      category: :pipeline,
      keys: [:run_id, :session, :project_id],
      doc: "Pipeline spawned with lead agent in tmux"
    },
    pipeline_completed: %{
      category: :pipeline,
      keys: [:run_id, :label],
      doc: "All pipeline tasks completed for a pipeline run"
    },
    pipeline_task_claimed: %{
      category: :pipeline,
      keys: [:run_id, :task_id, :external_id, :owner, :wave],
      doc: "Pipeline task claimed by a lead agent"
    },
    pipeline_task_completed: %{
      category: :pipeline,
      keys: [:run_id, :task_id, :external_id, :owner],
      doc: "Pipeline task marked completed after verification"
    },
    pipeline_task_failed: %{
      category: :pipeline,
      keys: [:run_id, :task_id, :external_id, :notes],
      doc: "Pipeline task marked failed"
    },
    pipeline_task_reset: %{
      category: :pipeline,
      keys: [:run_id, :task_id, :external_id],
      doc: "Stale or failed pipeline task reset to pending"
    },
    pipeline_tmux_gone: %{
      category: :pipeline,
      keys: [:run_id, :session],
      doc: "Pipeline tmux session no longer exists (liveness check)"
    },
    pipeline_health_report: %{
      category: :pipeline,
      keys: [:run_id, :healthy, :issue_count],
      doc: "Periodic health check result for a pipeline run"
    },
    pipeline_status: %{
      category: :pipeline,
      keys: [:state_map],
      doc: "Current pipeline status snapshot for the active project set"
    },
    pipeline_archived: %{
      category: :pipeline,
      keys: [:run_id, :label, :reason],
      doc: "Pipeline run archived by watchdog after unexpected death"
    },
    pipeline_reconciled: %{
      category: :pipeline,
      keys: [:pipeline_id, :run_id, :action],
      doc: "Pipeline reconciler took action on an orphaned pipeline (AD-8 safety net)"
    }
  }

  @archon_cleanup_defs %{
    run_cleanup_needed: %{
      category: :cleanup,
      keys: [:run_id, :action],
      doc: "TeamWatchdog detected a run needing cleanup; Oban worker reacts"
    },
    session_cleanup_needed: %{
      category: :cleanup,
      keys: [:session, :action],
      doc: "TeamWatchdog detected a session needing cleanup; Oban worker reacts"
    }
  }

  @settings_defs %{
    settings_project_created: %{
      category: :system,
      keys: [:project_id, :name, :is_active],
      doc: "Settings project created"
    },
    settings_project_updated: %{
      category: :system,
      keys: [:project_id, :name, :is_active],
      doc: "Settings project updated"
    },
    settings_project_destroyed: %{
      category: :system,
      keys: [:project_id, :name, :is_active],
      doc: "Settings project destroyed"
    }
  }

  @signals @core_defs
           |> Map.merge(@gateway_agent_defs)
           |> Map.merge(@team_monitoring_defs)
           |> Map.merge(@mes_defs)
           |> Map.merge(@planning_pipeline_defs)
           |> Map.merge(@archon_cleanup_defs)
           |> Map.merge(@settings_defs)

  @catalog Map.new(@signals, fn {k, v} -> {k, Map.put_new(v, :dynamic, false)} end)
  @categories @catalog |> Map.values() |> Enum.map(& &1.category) |> Enum.uniq() |> Enum.sort()
  @static_signals @catalog |> Enum.reject(fn {_, v} -> v.dynamic end) |> Enum.map(&elem(&1, 0))

  @doc "Look up a signal definition by name. Returns nil if not found."
  @spec lookup(atom()) :: signal_def() | nil
  def lookup(name), do: Map.get(@catalog, name)

  @doc "Look up a signal definition, deriving one from name prefix if absent."
  @spec lookup_or_derive(atom()) :: signal_def()
  def lookup_or_derive(name) do
    Map.get(@catalog, name) || derive(name)
  end

  @doc "Derive a signal definition from its name prefix. Allows signals to work without catalog entries."
  @spec derive(atom()) :: signal_def()
  def derive(name) do
    prefix =
      name
      |> Atom.to_string()
      |> String.split("_", parts: 2)
      |> hd()

    category = Enum.find(@categories, :uncategorized, &(Atom.to_string(&1) == prefix))
    %{category: category, keys: [], dynamic: false, doc: "auto-derived"}
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
