# Signal Emission Map

Every emit/broadcast/send in the codebase. Exhaustive.

## Signals.emit/2 (name, payload)

| Signal | File:Line | Payload | Dynamic? |
|--------|-----------|---------|----------|
| `:heartbeat` | agent_watchdog.ex:68 | `%{count: n}` | static |
| `:agent_crashed` | agent_watchdog.ex:146,152 | `%{session_id:, team_name:}` | static |
| `:nudge_warning` | agent_watchdog.ex:244 | `%{session_id:, agent_name:, level: 0}` | static |
| `:nudge_sent` | agent_watchdog.ex:272 | `%{session_id:, agent_name:, level: 1}` | static |
| `:nudge_escalated` | agent_watchdog.ex:279 | `%{session_id:, agent_name:, level: 2}` | static |
| `:nudge_zombie` | agent_watchdog.ex:289 | `%{session_id:, agent_name:, level: 3}` | static |
| `signal_name` | agent_watchdog.ex:409 | `%{session_id:, reason:/summary:}` | **DYNAMIC** (`:agent_done` or `:agent_blocked`) |
| `:entropy_alert` | entropy_tracker.ex:155 | `%{session_id:, entropy_score:}` | static |
| `:node_state_update` | entropy_tracker.ex:156,160,165 | `%{agent_id:, state: "alert_entropy"/"blocked"/"active"}` | static |
| `:protocol_update` | protocol_tracker.ex:55 | `%{stats_map: stats}` | static |
| `:new_event` | event_stream.ex:45 | `%{event: event}` | static |
| `:new_event` | event_stream.ex:62 | `%{name:, attrs:}` | static (publish_fact, DEAD) |
| `:agent_evicted` | event_stream.ex:201 | `%{session_id:}` | static |
| `:session_ended` | event_stream.ex:233 | `%{session_id:, status: :ended}` | static |
| `:session_started` | agent_lifecycle.ex:94 | `%{session_id:, tmux_session:, cwd:, model:, os_pid:}` | static |
| `signal` | agent_lifecycle.ex:68 | `%{team_name:}` | **DYNAMIC** (`:team_create_requested` or `:team_delete_requested`) |
| `:fleet_changed` | bus.ex:182 | `%{}` | static (**BUG**: empty, catalog expects `:agent_id`) |
| `:message_delivered` | bus.ex:187 | `%{agent_id:, msg_map:}` | static |
| `:decision_log` | event_bridge.ex:42 | `%{log: log}` | static |
| `:topology_snapshot` | event_bridge.ex:54 | `build_topology(node_map)` | static |
| `:decision_log` | gateway_controller.ex:26 | `%{log: log}` | static |
| `:decision_log` | hitl/events.ex:24 | `%{log: msg}` | static |
| `:hitl_auto_released` | hitl/events.ex:30 | `%{session_id:}` | static |
| `:hitl_operator_approved` | dashboard_session_control.ex:93 | `%{session_id:}` | static |
| `:hitl_operator_rejected` | dashboard_session_control.ex:106 | `%{session_id:}` | static |
| `:agent_stopped` | dashboard_session_control.ex:155 | `%{session_id:, reason: "dashboard_shutdown"}` | static |
| `:mesh_pause` | dashboard_session_control.ex:221 | `%{initiated_by: "god_mode"}` | static |
| `:run_cleanup_needed` | team_watchdog.ex:130,134 | `%{run_id:, action: :archive/:reset_tasks}` | static |
| `:session_cleanup_needed` | team_watchdog.ex:138,142 | `%{session:, action: :disband/:kill}` | static |
| `:pipeline_created` | loader.ex:58 | `%{run_id:, source:, label:, task_count:}` | static |
| `:pipeline_ready` | spawn.ex:76 | `%{run_id:, session:, project_id:, agent_count:, worker_count:}` | static |
| `:planning_team_ready` | spawn.ex:113 | `%{session:, mode:, project_id:, agent_count:}` | static |
| `:planning_team_spawn_failed` | spawn.ex:123 | `%{session:, reason:}` | static |
| `:mes_team_killed` | spawn.ex:169 | `%{session:}` | static |
| `:mes_cleanup` | spawn.ex:208,225,229,288 | `%{target: "..."}` | static (dynamic string value) |
| `:run_complete` | runner.ex:280 | `run_complete_payload(state)` | static |
| `:run_terminated` | runner.ex:285 | `%{kind:, run_id:, session:}` | static |
| `:mes_cycle_failed` | runner.ex:335 | `%{run_id:, reason:}` | static |
| `:mes_corrective_agent_spawned` | runner.ex:367 | `%{run_id:, session:, attempt:}` | static |
| `:mes_corrective_agent_failed` | runner.ex:374 | `%{run_id:, session:, reason:}` | static |
| `:pipeline_health_report` | runner.ex:407 | `%{run_id:, healthy:, issue_count:}` | static |
| `signal` | runner.ex:589 | nil-filtered terminate payload | **DYNAMIC** (from `state.config.signals.terminated`) |
| `:run_complete` | runner/modes.ex:61 | `%{kind: :mes, run_id:, session:}` | static |
| `:planning_run_complete` | runner/modes.ex:94 | `%{run_id:, mode:, session:, delivered_by:}` | static |
| `:pipeline_archived` | archive_run_worker.ex:24 | `%{run_id:, label:, reason: "watchdog"}` | static |
| `:mes_tick` | mes_tick.ex:18,21,25 | `%{paused: true}` or `%{active_runs:, total_runs:}` | static |
| `:mes_cycle_skipped` | mes_tick.ex:26 | `%{active_runs:}` | static |
| `:mes_cycle_started` | mes_tick.ex:44 | `%{run_id:, team_name:}` | static |
| `:mes_cycle_failed` | mes_tick.ex:47 | `%{run_id:, reason:}` | static |
| `:pipeline_status` | project_discovery_worker.ex:24 | `%{state_map:}` | static |
| `:pipeline_health_report` | health_check_worker.ex:26 | `%{run_id:, healthy:, issue_count:}` | static |
| `:mes_maintenance_init` | orphan_sweep_worker.ex:17 | `%{monitored:}` | static |
| `:mes_maintenance_error` | orphan_sweep_worker.ex:25 | `%{run_id: "sweep", reason:}` | static |
| `:pipeline_reconciled` | pipeline_reconciler_worker.ex:49 | `%{pipeline_id:, run_id:, action: :archived}` | static |
| `:mes_project_created` | project_ingestor.ex:238 | `%{project_id:, title:, run_id:}` | static |
| `:mes_research_ingested` | research_ingestor.ex:57 | `%{run_id:, project_id:, episode_id:}` | static |
| `:mes_research_ingest_failed` | research_ingestor.ex:68 | `%{run_id:, reason:}` | static |
| `:mes_plugin_compile_failed` | completion_handler.ex:72 | `%{run_id:, project_id:, reason:}` | static |
| `:mes_output_unhandled` | completion_handler.ex:85 | `%{run_id:, project_id:, output_kind:}` | static |
| `:fleet_changed` | agent_process.ex:305 | `%{agent_id:}` | static |
| `:mes_agent_tmux_gone` | agent_process.ex:287 | `%{agent_id:, tmux:}` | static |
| `:agent_started` | agent_lifecycle.ex:13 | `%{session_id:, role:, team:}` | static |
| `:agent_paused` | agent_lifecycle.ex:19 | `%{session_id:}` | static |
| `:agent_resumed` | agent_lifecycle.ex:25 | `%{session_id:}` | static |
| `:agent_stopped` | agent_lifecycle.ex:31 | `%{session_id:, reason:}` | static |
| `:team_created` | team_supervisor.ex:99 | `%{name:, project:, strategy:}` | static |
| `:team_disbanded` | fleet_supervisor.ex:53,62 | `%{team_name:, pid:, result:}` | static |
| `:fleet_changed` | tmux_discovery.ex:52 | `%{}` | static |
| `:agent_reaped` | tmux_discovery.ex:78 | `%{session_id:}` | static |
| `:agent_discovered` | tmux_discovery.ex:92 | `%{session_id:}` | static |
| `:hosts_changed` | host_registry.ex:162 | `%{}` | static |
| `:mes_scheduler_paused` | mes_scheduler.ex:14 | `%{}` | static |
| `:mes_scheduler_resumed` | mes_scheduler.ex:22 | `%{}` | static |
| `:mes_operator_ensured` | lifecycle_supervisor.ex:46,55,58 | `%{status: "already_alive"/"created"}` | static |
| `:mes_plugin_loaded` | plugin_loader.ex:26 | `%{project_id:, plugin:, modules:}` | static |
| `:mes_pipeline_generated` | dashboard_mes_handlers.ex:72 | `%{project_id:}` | static |
| `:mes_pipeline_launched` | dashboard_mes_handlers.ex:87 | `%{project_id:, session:}` | static |
| `:mes_project_picked_up` | dashboard_mes_handlers.ex:103 | `%{project_id:, session_id: "manual"}` | static |
| `name` | signals/event.ex:32 | `data` | **DYNAMIC** (Ash action `:emit`) |
| `name` | from_ash.ex:19 | `extract_fn.(data, action)` | **DYNAMIC** (see FromAsh mapping below) |
| `:tasks_updated` | board.ex:231 | `%{team_name:}` | static |

## Signals.emit/3 (name, scope_id, payload) -- scoped/dynamic signals

| Signal | Scope | File:Line | Payload |
|--------|-------|-----------|---------|
| `:agent_event` | `agent_id` | event_stream.ex:228 | `%{event:}` |
| `:agent_message_intercepted` | `session_id` | event_stream.ex:275 | `%{from:, to:, content:, type:}` |
| `:dag_delta` | `session_id` | causal_dag.ex:419 | `%{session_id:, added_nodes:}` |
| `:team_spawn_requested` | `request_id` | workshop/spawn.ex:59 | `%{team_name:, spec:, source:}` |
| `:team_spawn_started` | `request_id` | team_spawn_handler.ex:58 | `%{team_name:, agent_count:, source:}` |
| `:team_spawn_ready` | `request_id` | team_spawn_handler.ex:37 | `%{session:, team_name:, agent_count:, source:}` |
| `:team_spawn_failed` | `request_id` | team_spawn_handler.ex:45 | `%{team_name:, reason:, source:}` |
| `:agent_instructions` | `agent_class` | dashboard_session_control.ex:203 | `%{agent_class:, instructions:}` |
| `:gate_open` | `session_id` | hitl/events.ex:12 | `%{session_id:}` |
| `:gate_close` | `session_id` | hitl/events.ex:18 | `%{session_id:}` |
| `:terminal_output` | `session_id` | output_capture.ex:112 | `%{session_id:, output:}` |
| `:scheduled_job` | `agent_id` | scheduled_job.ex:26,40 | `%{agent_id:, payload:}` |
| `:memory_changed` | `agent_name` | memory_store.ex:287,467 | `%{agent_name:, event: :created/:archival_insert}` |
| `signal` | `team_name` | board.ex:230 | `payload` | **DYNAMIC** |
| `args.name` | `args.scope_id` | event.ex:57 | `args.data` | **DYNAMIC** (Ash action) |

## FromAsh Notifier Mapping (from_ash.ex)

| Resource | Action | Signal | Payload keys |
|----------|--------|--------|-------------|
| Pipeline | :create | `:pipeline_created` | run_id, label, source |
| Pipeline | :complete | `:pipeline_completed` | run_id, label, source |
| Pipeline | :fail | `:pipeline_completed` | run_id, label, source |
| Pipeline | :archive | `:pipeline_archived` | run_id, label, reason |
| PipelineTask | :claim | `:pipeline_task_claimed` | task_id, run_id, external_id, subject, status, owner |
| PipelineTask | :complete | `:pipeline_task_completed` | (same) |
| PipelineTask | :fail | `:pipeline_task_failed` | (same) |
| PipelineTask | :reset | `:pipeline_task_reset` | (same) |
| Project | :create | `:project_created` | id, project_id, title, type |
| Project | :advance | `:project_advanced` | id, project_id, title, type |
| Project | :add_artifact | `:project_artifact_created` | project_id |
| Project | :add_roadmap_item | `:project_roadmap_item_created` | project_id |
| Project | :pick_up | `:mes_project_picked_up` | project_id, title, plugin, session_id |
| Project | :mark_compiled | `:mes_project_compiled` | (same) |
| Project | :mark_loaded | `:mes_plugin_loaded` | (same) |
| Project | :mark_failed | `:mes_project_failed` | (same) |
| WebhookDelivery | :enqueue | `:webhook_delivery_enqueued` | delivery_id, agent_id, target_url, status, attempt_count |
| WebhookDelivery | :mark_delivered | `:webhook_delivery_delivered` | (same) |
| WebhookDelivery | :mark_dead | `:dead_letter` | (same) |
| HITLInterventionEvent | :record | `:hitl_intervention_recorded` | event_id, session_id, agent_id, operator_id, action, details |
| CronJob | :schedule_once | `:cron_job_scheduled` | job_id, agent_id, next_fire_at |
| CronJob | :reschedule | `:cron_job_rescheduled` | (same) |
| SettingsProject | :create | `:settings_project_created` | project_id, name, is_active |
| SettingsProject | :update | `:settings_project_updated` | (same) |
| SettingsProject | :destroy | `:settings_project_destroyed` | (same) |

## Raw PubSub.broadcast (bypassing Signals layer)

| Topic | File:Line | Message shape |
|-------|-----------|---------------|
| `"signals:feed"` | buffer.ex:46 | `{:signal, seq, %Message{}}` |
| `topic` (dynamic) | runtime.ex:106 | `%Message{}` (the core transport) |

## Raw PubSub.subscribe (bypassing Signals layer)

| Topic | File:Line | Purpose |
|-------|-----------|---------|
| `"signals:feed"` | dashboard_live.ex:132 | UI signal feed |
| `"agent:#{session_id}"` | dashboard_messaging_handlers.ex:88 | Per-agent mailbox |
| `"plugin:#{app_name}"` | plugin_scaffold.ex:200 | Plugin template |

## Bus.send calls

| File:Line | from | to | content | type |
|-----------|------|-----|---------|------|
| gateway_rpc_controller.ex:19 | dynamic | dynamic | dynamic | default |
| dashboard_session_control.ex:39 | `"operator"` | session_id | pause message | `:session_control` |
| dashboard_session_control.ex:64 | `"operator"` | session_id | resume message | `:session_control` |
| dashboard_session_control.ex:119 | `"operator"` | session_id | shutdown message | `:session_control` |
| operations.ex:89 | dynamic | dynamic | dynamic | `:message` (MCP) |
| operations.ex:130 | `"archon"` | dynamic | dynamic | default |
| dashboard_pipeline_handlers.ex:154 | `"operator"` | dynamic | dynamic | default |
| agent_watchdog.ex:259 | `"ichor"` | session_id | nudge message | `:nudge` |
| dashboard_messaging_handlers.ex:15 | `"operator"` | sid | content | default |
| dashboard_messaging_handlers.ex:39 | `"operator"` | `"team:#{name}"` | content | default |
| dashboard_messaging_handlers.ex:63 | `"operator"` | sid | content | `:context_push` |
| dashboard_messaging_handlers.ex:100 | `"operator"` | target | content | default |
