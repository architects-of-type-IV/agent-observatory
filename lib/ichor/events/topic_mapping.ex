defmodule Ichor.Events.TopicMapping do
  @moduledoc """
  Maps legacy atom-based signal names to dot-delimited domain fact topics.

  Used by the Runtime bridge to convert old-style `Signals.emit(:agent_started, data)`
  into normalized `%Event{topic: "agent.process.started"}` envelopes.
  """

  @mapping %{
    # -- agent domain --
    agent_started: "agent.process.started",
    agent_paused: "agent.process.paused",
    agent_resumed: "agent.process.resumed",
    agent_stopped: "agent.process.stopped",
    agent_evicted: "agent.process.evicted",
    agent_reaped: "agent.process.reaped",
    agent_discovered: "agent.process.discovered",
    agent_crashed: "agent.process.crashed",
    agent_spawned: "agent.process.spawned",
    session_started: "agent.session.started",
    session_ended: "agent.session.ended",
    agent_tmux_gone: "agent.tmux.gone",
    terminal_output: "agent.terminal.output_received",
    agent_event: "agent.event.received",
    agent_message_intercepted: "agent.message.intercepted",
    mailbox_message: "agent.mailbox.message_received",
    agent_instructions: "agent.instructions.pushed",
    scheduled_job: "agent.job.fired",
    agent_done: "agent.work.completed",
    agent_blocked: "agent.work.blocked",

    # -- fleet domain --
    team_created: "fleet.team.created",
    team_disbanded: "fleet.team.disbanded",
    team_create_requested: "fleet.team.create_requested",
    team_delete_requested: "fleet.team.delete_requested",
    team_spawn_requested: "fleet.team.spawn_requested",
    team_spawn_started: "fleet.team.spawn_started",
    team_spawn_ready: "fleet.team.spawn_completed",
    team_spawn_failed: "fleet.team.spawn_failed",
    hosts_changed: "fleet.cluster.node_changed",
    fleet_changed: "fleet.registry.changed",
    run_complete: "fleet.run.completed",
    run_terminated: "fleet.run.terminated",

    # -- team domain --
    task_created: "team.task.created",
    task_updated: "team.task.updated",
    task_deleted: "team.task.deleted",
    tasks_updated: "team.tasklist.refreshed",

    # -- monitoring domain --
    protocol_update: "monitoring.protocol.stats_recomputed",
    gate_passed: "monitoring.gate.passed",
    gate_failed: "monitoring.gate.failed",

    # -- nudge domain --
    nudge_warning: "nudge.escalation.warned",
    nudge_sent: "nudge.escalation.nudged",
    nudge_escalated: "nudge.escalation.hitl_paused",
    nudge_zombie: "nudge.escalation.zombied",

    # -- gateway domain --
    decision_log: "gateway.message.routed",
    schema_violation: "gateway.schema.violated",
    node_state_update: "gateway.topology.node_updated",
    entropy_alert: "gateway.entropy.detected",
    topology_snapshot: "gateway.topology.snapshot_taken",
    capability_update: "gateway.capability.updated",
    dead_letter: "gateway.webhook.dead_lettered",
    webhook_delivery_enqueued: "gateway.webhook.enqueued",
    webhook_delivery_delivered: "gateway.webhook.delivered",
    gateway_audit: "gateway.routing.audited",
    mesh_pause: "gateway.mesh.paused",
    cron_job_scheduled: "gateway.cron.scheduled",
    cron_job_rescheduled: "gateway.cron.rescheduled",

    # -- hitl domain --
    gate_open: "hitl.gate.opened",
    gate_close: "hitl.gate.closed",
    hitl_auto_released: "hitl.gate.auto_released",
    hitl_operator_approved: "hitl.operator.approved",
    hitl_operator_rejected: "hitl.operator.rejected",
    hitl_intervention_recorded: "hitl.operator.intervention_recorded",

    # -- mesh domain --
    dag_delta: "mesh.dag.updated",

    # -- memory domain --
    block_changed: "memory.block.modified",
    memory_changed: "memory.agent.changed",

    # -- message domain --
    message_delivered: "message.agent.delivered",

    # -- mes domain --
    mes_scheduler_paused: "mes.scheduler.paused",
    mes_scheduler_resumed: "mes.scheduler.resumed",
    mes_cycle_started: "mes.cycle.started",
    mes_cycle_skipped: "mes.cycle.skipped",
    mes_cycle_failed: "mes.cycle.failed",
    mes_cycle_timeout: "mes.cycle.timed_out",
    mes_run_started: "mes.run.started",
    mes_run_terminated: "mes.run.terminated",
    mes_maintenance_cleaned: "mes.maintenance.cleaned",
    mes_maintenance_error: "mes.maintenance.failed",
    mes_maintenance_skipped: "mes.maintenance.skipped",
    mes_tmux_session_created: "mes.tmux.session_created",
    mes_tmux_spawn_failed: "mes.tmux.spawn_failed",
    mes_team_ready: "mes.team.ready",
    mes_team_killed: "mes.team.killed",
    mes_team_spawn_failed: "mes.team.spawn_failed",
    mes_agent_registered: "mes.agent.registered",
    mes_agent_register_failed: "mes.agent.registration_failed",
    mes_agent_stopped: "mes.agent.stopped",
    mes_operator_ensured: "mes.operator.ensured",
    mes_project_created: "mes.project.created",
    mes_project_picked_up: "mes.project.claimed",
    mes_project_compiled: "mes.project.compiled",
    mes_project_failed: "mes.project.failed",
    mes_prompts_written: "mes.prompts.written",
    mes_cleanup: "mes.session.cleaned",
    mes_plugin_loaded: "mes.plugin.loaded",
    mes_plugin_compile_failed: "mes.plugin.compile_failed",
    mes_quality_gate_passed: "mes.gate.passed",
    mes_quality_gate_failed: "mes.gate.failed",
    mes_quality_gate_escalated: "mes.gate.escalated",
    mes_research_ingested: "mes.research.ingested",
    mes_research_ingest_failed: "mes.research.ingest_failed",
    mes_output_unhandled: "mes.output.unhandled",
    mes_pipeline_generated: "mes.pipeline.generated",
    mes_pipeline_launched: "mes.pipeline.launched",
    mes_corrective_agent_spawned: "mes.corrective_agent.spawned",
    mes_corrective_agent_failed: "mes.corrective_agent.spawn_failed",

    # -- planning domain --
    planning_team_ready: "planning.team.ready",
    planning_team_spawn_failed: "planning.team.spawn_failed",
    planning_team_killed: "planning.team.killed",
    planning_tmux_gone: "planning.tmux.gone",
    planning_run_complete: "planning.run.completed",
    planning_run_terminated: "planning.run.terminated",
    project_created: "planning.project.created",
    project_advanced: "planning.project.advanced",
    project_artifact_created: "planning.project.artifact_created",
    project_roadmap_item_created: "planning.project.roadmap_item_created",

    # -- pipeline domain --
    pipeline_created: "pipeline.run.created",
    pipeline_ready: "pipeline.run.started",
    pipeline_completed: "pipeline.run.completed",
    pipeline_archived: "pipeline.run.archived",
    pipeline_reconciled: "pipeline.run.reconciled",
    pipeline_task_claimed: "pipeline.task.claimed",
    pipeline_task_completed: "pipeline.task.completed",
    pipeline_task_failed: "pipeline.task.failed",
    pipeline_task_reset: "pipeline.task.reset",
    pipeline_tmux_gone: "pipeline.tmux.gone",
    pipeline_health_report: "pipeline.health.reported",
    pipeline_status: "pipeline.status.snapshot_taken",

    # -- cleanup domain --
    run_cleanup_needed: "cleanup.run.needed",
    session_cleanup_needed: "cleanup.session.needed",

    # -- settings domain --
    settings_project_created: "settings.project.created",
    settings_project_updated: "settings.project.updated",
    settings_project_destroyed: "settings.project.deleted",

    # -- system domain --
    dashboard_command: "system.dashboard.command_received"
  }

  # Infrastructure noise -- excluded from the event pipeline
  @noise MapSet.new([
           :heartbeat,
           :registry_changed,
           :new_event,
           :mes_scheduler_init,
           :mes_run_init,
           :planning_run_init,
           :mes_maintenance_init,
           :mes_tmux_spawning,
           :mes_tmux_window_created,
           :mes_tick,
           :watchdog_sweep
         ])

  @spec topic(atom()) :: {:ok, String.t()} | :noise | :unmapped
  def topic(signal_name) do
    cond do
      signal_name in @noise -> :noise
      Map.has_key?(@mapping, signal_name) -> {:ok, Map.fetch!(@mapping, signal_name)}
      true -> :unmapped
    end
  end

  @spec noise?(atom()) :: boolean()
  def noise?(signal_name), do: signal_name in @noise

  @spec all_topics() :: %{atom() => String.t()}
  def all_topics, do: @mapping
end
