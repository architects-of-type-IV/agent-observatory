defmodule Ichor.Events.Registry do
  @moduledoc """
  Event-to-category routing registry.

  Maps every known signal name to its PubSub category and scoping mode.
  Source of truth for `Runtime.emit/subscribe` topic resolution and the
  /signals catalog page.
  """

  @type entry :: %{category: atom(), dynamic: boolean(), doc: String.t()}

  # ── Fleet lifecycle ──────────────────────────────────────────────────

  @fleet %{
    agent_started: %{doc: "AgentProcess init"},
    agent_paused: %{doc: "Agent paused"},
    agent_resumed: %{doc: "Agent resumed"},
    agent_stopped: %{doc: "AgentProcess terminated"},
    agent_evicted: %{doc: "Agent evicted due to missed heartbeats"},
    agent_reaped: %{doc: "Dead agent reaped by TmuxDiscovery"},
    agent_discovered: %{doc: "Agent discovered via tmux session scan"},
    agent_tmux_gone: %{doc: "Agent's tmux window no longer exists"},
    session_started: %{doc: "New agent session started"},
    session_ended: %{doc: "Agent session ended"},
    team_created: %{doc: "New team started"},
    team_disbanded: %{doc: "Team removed"},
    team_spawn_requested: %{doc: "Team spawn requested", dynamic: true},
    team_spawn_started: %{doc: "Spawn request accepted", dynamic: true},
    team_spawn_ready: %{doc: "Requested team spawn completed", dynamic: true},
    team_spawn_failed: %{doc: "Requested team spawn failed", dynamic: true},
    team_create_requested: %{doc: "TeamCreate tool intercepted"},
    team_delete_requested: %{doc: "TeamDelete tool intercepted"},
    run_complete: %{doc: "Run completed cleanly"},
    run_terminated: %{doc: "Run process terminated"},
    hosts_changed: %{doc: "Cluster node joined/departed"},
    fleet_changed: %{doc: "Agent Registry metadata changed"}
  }

  # ── Agent-scoped events ─────────────────────────────────────────────

  @agent %{
    agent_crashed: %{doc: "Agent confirmed dead"},
    agent_spawned: %{doc: "Agent spawned via dashboard"},
    nudge_warning: %{doc: "Nudge escalation: warn"},
    nudge_sent: %{doc: "Nudge escalation: tmux nudge sent"},
    nudge_escalated: %{doc: "Nudge escalation: escalated"},
    nudge_zombie: %{doc: "Nudge escalation: zombie"},
    agent_event: %{doc: "Per-agent event stream", dynamic: true},
    agent_message_intercepted: %{doc: "Hook-intercepted SendMessage", dynamic: true},
    terminal_output: %{doc: "Tmux output", dynamic: true},
    mailbox_message: %{doc: "Direct message to agent", dynamic: true},
    agent_instructions: %{doc: "Pushed instructions", dynamic: true},
    scheduled_job: %{doc: "Cron job fired", dynamic: true}
  }

  # ── System ──────────────────────────────────────────────────────────

  @system %{
    heartbeat: %{doc: "Monotonic counter every 5s"},
    registry_changed: %{doc: "Agent registry modified"},
    dashboard_command: %{doc: "External command to dashboard"},
    settings_project_created: %{doc: "Settings project created"},
    settings_project_updated: %{doc: "Settings project updated"},
    settings_project_destroyed: %{doc: "Settings project destroyed"}
  }

  # ── Events + Messages + Memory ──────────────────────────────────────

  @events %{
    new_event: %{doc: "Hook event ingested by EventController"}
  }

  @messages %{
    message_delivered: %{doc: "Message delivered to agent"}
  }

  @memory %{
    block_changed: %{doc: "Memory block modified"},
    memory_changed: %{doc: "Per-agent memory change", dynamic: true}
  }

  # ── Team monitoring ─────────────────────────────────────────────────

  @team %{
    task_created: %{doc: "New task added", dynamic: true},
    task_updated: %{doc: "Task status changed", dynamic: true},
    task_deleted: %{doc: "Task removed", dynamic: true},
    tasks_updated: %{doc: "Team task list changed"}
  }

  @monitoring %{
    protocol_update: %{doc: "Protocol stats recomputed"},
    gate_passed: %{doc: "Quality gate passed"},
    gate_failed: %{doc: "Quality gate failed"},
    agent_done: %{doc: "Agent signalled DONE"},
    agent_blocked: %{doc: "Agent signalled BLOCKED"}
  }

  # ── Gateway ─────────────────────────────────────────────────────────

  @gateway %{
    schema_violation: %{doc: "Schema validation failure"},
    node_state_update: %{doc: "Topology node change"},
    entropy_alert: %{doc: "Repeated pattern detected"},
    topology_snapshot: %{doc: "Full topology snapshot"},
    capability_update: %{doc: "Agent capability map changed"},
    dead_letter: %{doc: "Failed webhook to DLQ"},
    webhook_delivery_enqueued: %{doc: "Webhook delivery job enqueued"},
    webhook_delivery_delivered: %{doc: "Webhook delivery confirmed"},
    gateway_audit: %{doc: "Message routing audit"},
    cron_job_scheduled: %{doc: "Cron job created via Ash action"},
    cron_job_rescheduled: %{doc: "Cron job rescheduled via Ash action"}
  }

  # ── MES ─────────────────────────────────────────────────────────────

  @mes %{
    mes_scheduler_init: %{doc: "MES scheduler initialized"},
    mes_scheduler_paused: %{doc: "MES scheduler paused"},
    mes_scheduler_resumed: %{doc: "MES scheduler resumed"},
    mes_tick: %{doc: "MES scheduler tick fired"},
    mes_cycle_started: %{doc: "MES scheduler spawned a new team"},
    mes_cycle_skipped: %{doc: "MES scheduler skipped tick"},
    mes_cycle_failed: %{doc: "MES run failed to start"},
    mes_cycle_timeout: %{doc: "MES team run exceeded budget"},
    mes_run_init: %{doc: "MES RunProcess initializing"},
    mes_run_started: %{doc: "MES team spawned"},
    mes_run_terminated: %{doc: "MES RunProcess terminated"},
    mes_maintenance_init: %{doc: "MES maintenance sweep initialized"},
    mes_maintenance_cleaned: %{doc: "MES maintenance cleaned up resources"},
    mes_maintenance_error: %{doc: "MES maintenance error"},
    mes_maintenance_skipped: %{doc: "MES maintenance skipped cleanup"},
    mes_prompts_written: %{doc: "MES prompt files written"},
    mes_tmux_spawning: %{doc: "MES about to create tmux session"},
    mes_tmux_session_created: %{doc: "MES tmux session created"},
    mes_tmux_spawn_failed: %{doc: "MES tmux creation failed"},
    mes_tmux_window_created: %{doc: "MES tmux window created"},
    mes_team_ready: %{doc: "All agents spawned in tmux"},
    mes_team_killed: %{doc: "MES tmux session killed"},
    mes_agent_registered: %{doc: "MES agent registered in BEAM"},
    mes_agent_register_failed: %{doc: "MES agent registration failed"},
    mes_team_spawn_failed: %{doc: "MES team creation failed"},
    mes_operator_ensured: %{doc: "MES operator verified"},
    mes_cleanup: %{doc: "MES cleanup of old resources"},
    mes_project_created: %{doc: "Coordinator submitted a brief artifact"},
    mes_project_picked_up: %{doc: "Implementation team claimed a project"},
    mes_plugin_loaded: %{doc: "Plugin hot-loaded into BEAM"},
    mes_quality_gate_passed: %{doc: "MES quality gate passed"},
    mes_quality_gate_failed: %{doc: "MES quality gate failed"},
    mes_quality_gate_escalated: %{doc: "MES quality gate escalated"},
    mes_agent_stopped: %{doc: "MES agent process stopped"},
    mes_research_ingested: %{doc: "Research brief ingested"},
    mes_research_ingest_failed: %{doc: "Research ingest failed"},
    mes_project_compiled: %{doc: "MES project compiled"},
    mes_project_failed: %{doc: "MES project failed"},
    mes_plugin_compile_failed: %{doc: "Plugin compile/load failed"},
    mes_output_unhandled: %{doc: "No registered output handler"},
    mes_pipeline_generated: %{doc: "Pipeline tasks.jsonl generated"},
    mes_pipeline_launched: %{doc: "Pipeline build team launched"},
    mes_corrective_agent_spawned: %{doc: "Corrective agent spawned"},
    mes_corrective_agent_failed: %{doc: "Corrective agent spawn failed"}
  }

  # ── Planning + Pipeline ─────────────────────────────────────────────

  @planning %{
    planning_team_ready: %{doc: "Planning mode team spawned"},
    planning_team_spawn_failed: %{doc: "Planning mode team failed"},
    planning_team_killed: %{doc: "Planning tmux session killed"},
    planning_run_init: %{doc: "RunProcess monitoring planning run"},
    planning_tmux_gone: %{doc: "Planning tmux session gone"},
    planning_run_complete: %{doc: "Planning run completed"},
    planning_run_terminated: %{doc: "RunProcess terminated"},
    project_created: %{doc: "Project created"},
    project_advanced: %{doc: "Project advanced"},
    project_artifact_created: %{doc: "Project artifact added"},
    project_roadmap_item_created: %{doc: "Project roadmap item added"}
  }

  @pipeline %{
    pipeline_created: %{doc: "Pipeline created"},
    pipeline_ready: %{doc: "Pipeline spawned with lead agent"},
    pipeline_completed: %{doc: "All pipeline tasks completed"},
    pipeline_task_claimed: %{doc: "Pipeline task claimed"},
    pipeline_task_completed: %{doc: "Pipeline task completed"},
    pipeline_task_failed: %{doc: "Pipeline task failed"},
    pipeline_task_reset: %{doc: "Pipeline task reset to pending"},
    pipeline_tmux_gone: %{doc: "Pipeline tmux session gone"},
    pipeline_health_report: %{doc: "Periodic health check result"},
    pipeline_status: %{doc: "Pipeline status snapshot"},
    pipeline_archived: %{doc: "Pipeline archived by watchdog"},
    pipeline_reconciled: %{doc: "Pipeline reconciler action"}
  }

  # ── Compiled registry ───────────────────────────────────────────────

  @category_groups [
    {:fleet, @fleet},
    {:agent, @agent},
    {:system, @system},
    {:events, @events},
    {:messages, @messages},
    {:memory, @memory},
    {:team, @team},
    {:monitoring, @monitoring},
    {:gateway, @gateway},
    {:mes, @mes},
    {:planning, @planning},
    {:pipeline, @pipeline}
  ]

  @registry (for {cat, signals} <- @category_groups,
                 {name, info} <- signals,
                 into: %{} do
               {name,
                %{
                  category: cat,
                  dynamic: Map.get(info, :dynamic, false),
                  doc: info.doc
                }}
             end)

  @categories @category_groups |> Enum.map(&elem(&1, 0)) |> Enum.sort()
  @category_set MapSet.new(@categories)
  @dynamic_set @registry
               |> Enum.filter(fn {_, v} -> v.dynamic end)
               |> MapSet.new(fn {k, _} -> k end)

  @doc "Return the category for a signal name. Falls back to prefix-based derivation."
  @spec category_for(atom()) :: atom()
  def category_for(name) do
    case Map.get(@registry, name) do
      %{category: cat} -> cat
      nil -> derive_category(name)
    end
  end

  @doc "True if the signal supports scoped (per-session/per-team) emit."
  @spec dynamic?(atom()) :: boolean()
  def dynamic?(name), do: MapSet.member?(@dynamic_set, name)

  @doc "True if the given atom is a known signal category."
  @spec valid_category?(atom()) :: boolean()
  def valid_category?(cat), do: MapSet.member?(@category_set, cat)

  @doc "Return all known signal categories, sorted."
  @spec categories() :: [atom()]
  def categories, do: @categories

  @doc "Return the full registry as a map of name -> entry."
  @spec all() :: %{atom() => entry()}
  def all, do: @registry

  @doc "Return all signal entries for a given category, sorted by name."
  @spec by_category(atom()) :: [{atom(), entry()}]
  def by_category(cat) do
    @registry
    |> Enum.filter(fn {_, v} -> v.category == cat end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp derive_category(name) do
    prefix =
      name
      |> Atom.to_string()
      |> String.split("_", parts: 2)
      |> hd()

    Enum.find(@categories, :uncategorized, &(Atom.to_string(&1) == prefix))
  end
end
