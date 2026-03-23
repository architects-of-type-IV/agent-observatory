# Signal Catalog (143 signals, 16 categories)

Dumped from `Ichor.Signals.Catalog.all()`, sorted by category.

## :agent (12 signals)

| Signal | Keys | Dynamic |
|--------|------|---------|
| `:agent_crashed` | session_id, team_name | |
| `:agent_event` | event | dynamic |
| `:agent_instructions` | agent_class, instructions | dynamic |
| `:agent_message_intercepted` | from, to, content, type | dynamic |
| `:agent_spawned` | session_id, name, capability | |
| `:mailbox_message` | message | dynamic |
| `:nudge_escalated` | session_id, agent_name, level | |
| `:nudge_sent` | session_id, agent_name, level | |
| `:nudge_warning` | session_id, agent_name, level | |
| `:nudge_zombie` | session_id, agent_name, level | |
| `:scheduled_job` | agent_id, payload | dynamic |
| `:terminal_output` | session_id, output | dynamic |

## :cleanup (2 signals)

| Signal | Keys | Dynamic |
|--------|------|---------|
| `:run_cleanup_needed` | run_id, action | |
| `:session_cleanup_needed` | session, action | |

## :events (1 signal)

| Signal | Keys | Dynamic |
|--------|------|---------|
| `:new_event` | event | |

## :fleet (20 signals)

| Signal | Keys | Dynamic |
|--------|------|---------|
| `:agent_discovered` | session_id | |
| `:agent_evicted` | session_id | |
| `:agent_paused` | session_id | |
| `:agent_reaped` | session_id | |
| `:agent_resumed` | session_id | |
| `:agent_started` | session_id, role, team | |
| `:agent_stopped` | session_id, reason | |
| `:fleet_changed` | agent_id | |
| `:hosts_changed` | | |
| `:run_complete` | kind, run_id, session | |
| `:run_terminated` | kind, run_id, session | |
| `:session_ended` | session_id, status | |
| `:session_started` | session_id, tmux_session, cwd, model, os_pid | |
| `:team_create_requested` | team_name | |
| `:team_created` | name, project, strategy | |
| `:team_delete_requested` | team_name | |
| `:team_disbanded` | team_name | |
| `:team_spawn_failed` | team_name, reason, source | dynamic |
| `:team_spawn_ready` | session, team_name, agent_count, source | dynamic |
| `:team_spawn_requested` | team_name, spec, source | dynamic |
| `:team_spawn_started` | team_name, agent_count, source | dynamic |

## :gateway (12 signals)

| Signal | Keys | Dynamic |
|--------|------|---------|
| `:capability_update` | state_map | |
| `:cron_job_rescheduled` | job_id, agent_id, next_fire_at | |
| `:cron_job_scheduled` | job_id, agent_id, next_fire_at | |
| `:dead_letter` | delivery | |
| `:decision_log` | log | |
| `:entropy_alert` | session_id, entropy_score | |
| `:gateway_audit` | envelope_id, channel | |
| `:mesh_pause` | initiated_by | |
| `:node_state_update` | agent_id, state | |
| `:schema_violation` | event_map | |
| `:topology_snapshot` | nodes, edges | |
| `:webhook_delivery_delivered` | delivery_id, agent_id, target_url, status, attempt_count | |
| `:webhook_delivery_enqueued` | delivery_id, agent_id, target_url, status, attempt_count | |

## :hitl (6 signals)

| Signal | Keys | Dynamic |
|--------|------|---------|
| `:gate_close` | session_id | dynamic |
| `:gate_open` | session_id | dynamic |
| `:hitl_auto_released` | session_id | |
| `:hitl_intervention_recorded` | event_id, session_id, agent_id, operator_id, action, details | |
| `:hitl_operator_approved` | session_id | |
| `:hitl_operator_rejected` | session_id | |

## :memory (2 signals)

| Signal | Keys | Dynamic |
|--------|------|---------|
| `:block_changed` | block_id, label | |
| `:memory_changed` | agent_name, event | dynamic |

## :mes (45 signals)

| Signal | Keys | Dynamic |
|--------|------|---------|
| `:mes_agent_register_failed` | agent_name, reason | |
| `:mes_agent_registered` | agent_name, session | |
| `:mes_agent_stopped` | agent_id, role, team, reason | |
| `:mes_agent_tmux_gone` | agent_id, tmux_target | |
| `:mes_cleanup` | target | |
| `:mes_corrective_agent_failed` | run_id, session, reason | |
| `:mes_corrective_agent_spawned` | run_id, session, attempt | |
| `:mes_cycle_failed` | run_id, reason | |
| `:mes_cycle_skipped` | tick, active_runs | |
| `:mes_cycle_started` | run_id, team_name | |
| `:mes_cycle_timeout` | run_id, team_name | |
| `:mes_maintenance_cleaned` | run_id, trigger | |
| `:mes_maintenance_error` | run_id, reason | |
| `:mes_maintenance_init` | monitored | |
| `:mes_maintenance_skipped` | run_id, reason | |
| `:mes_operator_ensured` | status | |
| `:mes_output_unhandled` | run_id, project_id, output_kind | |
| `:mes_pipeline_generated` | project_id | |
| `:mes_pipeline_launched` | project_id, session | |
| `:mes_plugin_compile_failed` | run_id, project_id, reason | |
| `:mes_plugin_loaded` | project_id, plugin, modules | |
| `:mes_project_compiled` | project_id, title | |
| `:mes_project_created` | project_id, title, run_id | |
| `:mes_project_failed` | project_id, title | |
| `:mes_project_picked_up` | project_id, session_id | |
| `:mes_prompts_written` | run_id, agent_count | |
| `:mes_quality_gate_escalated` | run_id, gate, failure_count | |
| `:mes_quality_gate_failed` | run_id, gate, session_id, reason | |
| `:mes_quality_gate_passed` | run_id, gate, session_id | |
| `:mes_research_ingest_failed` | run_id, reason | |
| `:mes_research_ingested` | run_id, project_id, episode_id | |
| `:mes_run_init` | run_id, team_name | |
| `:mes_run_started` | run_id, session | |
| `:mes_run_terminated` | run_id | |
| `:mes_scheduler_init` | paused | |
| `:mes_scheduler_paused` | tick | |
| `:mes_scheduler_resumed` | tick | |
| `:mes_team_killed` | session | |
| `:mes_team_ready` | session, agent_count | |
| `:mes_team_spawn_failed` | session, reason | |
| `:mes_tick` | tick, active_runs | |
| `:mes_tmux_session_created` | session, agent_name | |
| `:mes_tmux_spawn_failed` | session, output, exit_code | |
| `:mes_tmux_spawning` | session, agent_name, command, tmux_args | |
| `:mes_tmux_window_created` | session, agent_name | |

## :mesh (1 signal)

| Signal | Keys | Dynamic |
|--------|------|---------|
| `:dag_delta` | session_id, added_nodes | dynamic |

## :messages (1 signal)

| Signal | Keys | Dynamic |
|--------|------|---------|
| `:message_delivered` | agent_id, msg_map | |

## :monitoring (6 signals)

| Signal | Keys | Dynamic |
|--------|------|---------|
| `:agent_blocked` | session_id, reason | |
| `:agent_done` | session_id, summary | |
| `:gate_failed` | session_id, task_id, output | |
| `:gate_passed` | session_id, task_id | |
| `:protocol_update` | stats_map | |
| `:watchdog_sweep` | orphaned_count | |

## :pipeline (14 signals)

| Signal | Keys | Dynamic |
|--------|------|---------|
| `:pipeline_archived` | run_id, label, reason | |
| `:pipeline_completed` | run_id, label | |
| `:pipeline_created` | run_id, source, label, task_count | |
| `:pipeline_health_report` | run_id, healthy, issue_count | |
| `:pipeline_ready` | run_id, session, project_id | |
| `:pipeline_reconciled` | pipeline_id, run_id, action | |
| `:pipeline_status` | state_map | |
| `:pipeline_task_claimed` | run_id, task_id, external_id, owner, wave | |
| `:pipeline_task_completed` | run_id, task_id, external_id, owner | |
| `:pipeline_task_failed` | run_id, task_id, external_id, notes | |
| `:pipeline_task_reset` | run_id, task_id, external_id | |
| `:pipeline_tmux_gone` | run_id, session | |

## :planning (8 signals)

| Signal | Keys | Dynamic |
|--------|------|---------|
| `:planning_run_complete` | run_id, mode, session, delivered_by | |
| `:planning_run_init` | run_id, mode, session | |
| `:planning_run_terminated` | run_id, mode | |
| `:planning_team_killed` | session | |
| `:planning_team_ready` | session, mode, project_id, agent_count | |
| `:planning_team_spawn_failed` | session, reason | |
| `:planning_tmux_gone` | run_id, session | |
| `:project_advanced` | id, project_id, title, type | |
| `:project_artifact_created` | project_id | |
| `:project_created` | id, project_id, title, type | |
| `:project_roadmap_item_created` | project_id | |

## :system (6 signals)

| Signal | Keys | Dynamic |
|--------|------|---------|
| `:dashboard_command` | command | |
| `:heartbeat` | count | |
| `:registry_changed` | | |
| `:settings_project_created` | project_id, name, is_active | |
| `:settings_project_destroyed` | project_id, name, is_active | |
| `:settings_project_updated` | project_id, name, is_active | |

## :team (4 signals)

| Signal | Keys | Dynamic |
|--------|------|---------|
| `:task_created` | task | dynamic |
| `:task_deleted` | task_id | dynamic |
| `:task_updated` | task | dynamic |
| `:tasks_updated` | team_name | |
