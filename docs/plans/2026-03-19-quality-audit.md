# Quality Audit Report
**Date:** 2026-03-19
**Scope:** `lib/ichor/` and `lib/ichor_web/` (read-only research, no edits)

---

## Summary

| Category | Count |
|---|---|
| Missing `@moduledoc` | 12 |
| `@moduledoc false` warranting review | 2 |
| Missing `@doc` on public functions (ichor/ only) | 326 |
| Missing `@spec` on public functions (ichor/ only) | 196 |
| Banner comments to remove | 19 |
| Missing `@enforce_keys` on structs | 8 |
| Missing `@type t` on structs | 5 |

---

## 1. Missing `@moduledoc` (12)

All 12 are in `ichor_web/`. The `ichor/` domain layer is fully documented.

```
lib/ichor_web/components/protocol_components.ex
lib/ichor_web/controllers/export_controller.ex
lib/ichor_web/controllers/gateway_controller.ex
lib/ichor_web/controllers/heartbeat_controller.ex
lib/ichor_web/controllers/noop_controller.ex
lib/ichor_web/controllers/page_html.ex
lib/ichor_web/controllers/webhook_controller.ex
lib/ichor_web/endpoint.ex
lib/ichor_web/live/dashboard_live.ex
lib/ichor_web/router.ex
lib/ichor_web/telemetry.ex
lib/ichor/repo.ex
```

### `@moduledoc false` review (2 candidates)

These have `@moduledoc false` but are not Ash resources, test support, or pure catalog definitions -- they may deserve real documentation:

- `lib/ichor/events/event.ex` -- Ash resource (acceptable)
- `lib/ichor/events/session.ex` -- Ash resource (acceptable)

The `signals/catalog/*_defs.ex` files have `@moduledoc false` and export only a `definitions/0` function -- acceptable for internal catalog fragments.

**Genuine candidates for upgrading from `@moduledoc false` to real docs:**
- None found. All `@moduledoc false` usages are either Ash resources, application entry, internal sub-modules of `decision_log.ex`, or LiveView component sub-files.

---

## 2. Missing `@doc` on public functions (326 in ichor/)

Note: `ichor_web/` components and LiveView functions are excluded (Phoenix template functions and LiveView callbacks do not require `@doc` per project rules). Multi-clause functions are deduplicated to first occurrence only.

### Domain/API modules (highest priority -- public surface area)

```
lib/ichor/mes.ex:19: get_project
lib/ichor/mes.ex:22: create_project
lib/ichor/mes.ex:28: loaded_projects
lib/ichor/mes.ex:36: all_projects
lib/ichor/mes.ex:44: mark_loaded
lib/ichor/mes.ex:48: mark_failed
lib/ichor/dag.ex:23: get_run
lib/ichor/dag.ex:29: runs_by_node
lib/ichor/dag.ex:32: runs_by_path
lib/ichor/dag.ex:35: jobs_for_run
lib/ichor/dag.ex:38: fetch_jobs_for_run
lib/ichor/observability.ex:27: list_events
lib/ichor/genesis.ex:44: get_node
lib/ichor/genesis.ex:49: node_by_project
lib/ichor/genesis.ex:54: create_node
lib/ichor/genesis.ex:59: advance_node
lib/ichor/genesis.ex:66: list_nodes
lib/ichor/genesis.ex:71: load_node
lib/ichor/protocol_tracker.ex:29: track_mailbox_delivery
lib/ichor/protocol_tracker.ex:34: track_command_write
lib/ichor/protocol_tracker.ex:39: track_gateway_broadcast
```

### Infrastructure modules

```
lib/ichor/mesh/decision_log.ex:247: major_version
lib/ichor/mesh/causal_dag.ex:34: insert
lib/ichor/mesh/causal_dag.ex:38: get_session_dag
lib/ichor/mesh/causal_dag.ex:42: get_children
lib/ichor/mesh/causal_dag.ex:46: signal_terminal
lib/ichor/signals/catalog.ex:33: lookup
lib/ichor/signals/catalog.ex:65: by_category
lib/ichor/signals/entry_formatter.ex:7: format
lib/ichor/signals/bus.ex:14: subscribe
lib/ichor/signals/bus.ex:17: unsubscribe
lib/ichor/signals/bus.ex:20: broadcast
lib/ichor/signals/catalog/mes_defs.ex:4: definitions
lib/ichor/signals/catalog/gateway_agent_defs.ex:4: definitions
lib/ichor/signals/catalog/core_defs.ex:4: definitions
lib/ichor/signals/catalog/genesis_dag_defs.ex:4: definitions
lib/ichor/signals/catalog/team_monitoring_defs.ex:4: definitions
```

### Workshop modules

```
lib/ichor/workshop/presets.ex:281: fetch
lib/ichor/workshop/presets.ex:289: apply
lib/ichor/workshop/presets.ex:307: spawn_order
lib/ichor/workshop/blueprint_state.ex:38: defaults
lib/ichor/workshop/blueprint_state.ex:54: clear
lib/ichor/workshop/blueprint_state.ex:59: add_agent
lib/ichor/workshop/blueprint_state.ex:69: select_agent
lib/ichor/workshop/blueprint_state.ex:72: move_agent
lib/ichor/workshop/blueprint_state.ex:79: update_agent
lib/ichor/workshop/blueprint_state.ex:99: remove_agent
lib/ichor/workshop/blueprint_state.ex:113: add_spawn_link
lib/ichor/workshop/blueprint_state.ex:127: remove_spawn_link
lib/ichor/workshop/blueprint_state.ex:132: add_comm_rule
lib/ichor/workshop/blueprint_state.ex:150: remove_comm_rule
lib/ichor/workshop/blueprint_state.ex:155: update_team
lib/ichor/workshop/blueprint_state.ex:164: apply_blueprint
lib/ichor/workshop/blueprint_state.ex:184: new_agent
lib/ichor/workshop/blueprint_state.ex:204: agent_type_agent
lib/ichor/workshop/blueprint_state.ex:217: to_persistence_params
lib/ichor/workshop/persistence.ex:10: save_blueprint
lib/ichor/workshop/persistence.ex:26: load_blueprint
lib/ichor/workshop/persistence.ex:33: delete_blueprint
lib/ichor/workshop/team_spec_builder.ex:11: build_from_state
lib/ichor/workshop/team_spec_builder.ex:57: session_name
lib/ichor/workshop/team_spec_builder.ex:60: prompt_dir
lib/ichor/workshop/team_spec_builder.ex:63: prompt_root_dir
lib/ichor/workshop/launcher.ex:10: launch
```

### Archon modules

```
lib/ichor/archon/signal_manager.ex:18: snapshot
lib/ichor/archon/signal_manager.ex:23: attention
lib/ichor/archon/memories_client.ex:79: search
lib/ichor/archon/memories_client.ex:97: ingest
lib/ichor/archon/memories_client.ex:117: query_memory
lib/ichor/archon/command_manifest.ex:48: unknown_command_help
lib/ichor/archon/team_watchdog/reactions.ex:20: react
lib/ichor/archon/chat/context_builder.ex:12: build_messages
lib/ichor/archon/chat/context_builder.ex:53: format_edges
lib/ichor/archon/chat/context_builder.ex:79: format_episodes
lib/ichor/archon/chat/response_formatter.ex:7: extract
lib/ichor/archon/chat/command_registry.ex:19: dispatch
lib/ichor/archon/chat/command_parser.ex:7: parse
lib/ichor/archon/chat/chain_builder.ex:45: build
lib/ichor/archon/signal_manager/reactions.ex:28: new_state
lib/ichor/archon/signal_manager/reactions.ex:38: ingest
```

### Tasks modules

```
lib/ichor/tasks/board.ex:8: create_task
lib/ichor/tasks/board.ex:15: update_task
lib/ichor/tasks/board.ex:22: delete_task
lib/ichor/tasks/jsonl_store.ex:8: heal_task
lib/ichor/tasks/jsonl_store.ex:10: reassign_task
lib/ichor/tasks/jsonl_store.ex:19: claim_task
lib/ichor/tasks/jsonl_store.ex:32: update_task_status
lib/ichor/tasks/pipeline.ex:8: heal_task
lib/ichor/tasks/pipeline.ex:10: reassign_task
lib/ichor/tasks/pipeline.ex:13: claim_task
lib/ichor/tasks/pipeline.ex:15: update_task_status
lib/ichor/tasks/team_store.ex:10: create_task
lib/ichor/tasks/team_store.ex:37: update_task
lib/ichor/tasks/team_store.ex:61: get_task
lib/ichor/tasks/team_store.ex:71: list_tasks
lib/ichor/tasks/team_store.ex:86: delete_task
lib/ichor/tasks/team_store.ex:102: next_task_id
```

### Tools modules

```
lib/ichor/tools/genesis_formatter.ex:6: to_map
lib/ichor/tools/genesis_formatter.ex:19: summarize
lib/ichor/tools/genesis_formatter.ex:25: stringify
lib/ichor/tools/genesis_formatter.ex:29: split_csv
lib/ichor/tools/genesis_formatter.ex:38: parse_enum
lib/ichor/tools/genesis_formatter.ex:44: put_if
lib/ichor/tools/agent_control.ex:10: spawn
lib/ichor/tools/agent_control.ex:28: stop
lib/ichor/tools/agent_control.ex:40: pause
lib/ichor/tools/agent_control.ex:58: resume
```

### DAG modules

```
lib/ichor/dag/handoff.ex:7: package_jobs
lib/ichor/dag/handoff.ex:21: job_packet
lib/ichor/dag/runtime_callbacks.ex:13: after_job_transition
lib/ichor/dag/exporter.ex:13: to_jsonl
lib/ichor/dag/exporter.ex:20: sync_to_file
lib/ichor/dag/graph.ex:78: edges
lib/ichor/dag/graph.ex:82: dag
lib/ichor/dag/graph.ex:85: critical_path
lib/ichor/dag/graph.ex:206: file_conflicts
lib/ichor/dag/actions.ex:11: heal_task
lib/ichor/dag/actions.ex:18: reassign_task
lib/ichor/dag/actions.ex:25: claim_task
lib/ichor/dag/actions.ex:32: reset_all_stale
lib/ichor/dag/actions.ex:49: trigger_gc
lib/ichor/dag/claims.ex:9: claim_task
lib/ichor/dag/claims.ex:12: heal_task
lib/ichor/dag/claims.ex:15: reassign_task
lib/ichor/dag/claims.ex:18: reset_stale
lib/ichor/dag/prompts.ex:20: coordinator
lib/ichor/dag/prompts.ex:71: lead
lib/ichor/dag/prompts.ex:121: worker
lib/ichor/dag/runtime.ex:24: set_active_project
lib/ichor/dag/runtime.ex:27: add_project
lib/ichor/dag/runtime.ex:30: heal_task
lib/ichor/dag/runtime.ex:33: reassign_task
lib/ichor/dag/runtime.ex:36: reset_all_stale
lib/ichor/dag/runtime.ex:39: trigger_gc
lib/ichor/dag/runtime.ex:45: claim_task
lib/ichor/dag/runtime_event_bridge.ex:10: after_job_transition
lib/ichor/dag/run_supervisor.ex:14: start_run
lib/ichor/dag/run_supervisor.ex:20: stop_run
lib/ichor/dag/run_supervisor.ex:31: list_active
lib/ichor/dag/analysis.ex:8: refresh_tasks
lib/ichor/dag/analysis.ex:43: parse_tasks_jsonl
lib/ichor/dag/analysis.ex:54: find_stale_tasks
lib/ichor/dag/discovery.ex:17: discover_projects
lib/ichor/dag/discovery.ex:27: scan_archives
lib/ichor/dag/gc.ex:9: trigger
lib/ichor/dag/worker_groups.ex:8: group
lib/ichor/dag/runtime_signals.ex:16: emit_run_created
lib/ichor/dag/runtime_signals.ex:27: emit_run_ready
lib/ichor/dag/runtime_signals.ex:38: emit_health_report
lib/ichor/dag/runtime_signals.ex:43: emit_tmux_gone
lib/ichor/dag/runtime_signals.ex:48: emit_run_completed
lib/ichor/dag/runtime_signals.ex:53: emit_job_transition
lib/ichor/dag/projects.ex:8: initial_state
lib/ichor/dag/projects.ex:20: set_active_project
lib/ichor/dag/projects.ex:28: add_project
lib/ichor/dag/projects.ex:41: refresh_discovered_projects
lib/ichor/dag/projects.ex:56: register_cwd
lib/ichor/dag/projects.ex:78: tasks_jsonl_path
lib/ichor/dag/projects.ex:85: tasks_jsonl_path_for_task
lib/ichor/dag/projects.ex:101: active_project_path
lib/ichor/dag/projects.ex:108: first_project_key
lib/ichor/dag/health_report.ex:21: parse_health_output
lib/ichor/dag/status.ex:16: set_active_project
lib/ichor/dag/status.ex:19: add_project
lib/ichor/dag/status.ex:22: health_report
lib/ichor/dag/spawner.ex:27: spawn
lib/ichor/dag/loader.ex:9: from_file
lib/ichor/dag/loader.ex:20: from_genesis
lib/ichor/dag/run_process.ex:38: via
lib/ichor/dag/run_process.ex:41: sync_job
lib/ichor/dag/health_checker.ex:28: check
lib/ichor/dag/health_checker.ex:35: analyze
```

### Fleet modules

```
lib/ichor/fleet/lookup.ex:9: find_agent
lib/ichor/fleet/lookup.ex:18: agent_session_id
lib/ichor/fleet/lookup.ex:22: agent_display_name
lib/ichor/fleet/runtime_view.ex:8: resolve_selected_team
lib/ichor/fleet/runtime_view.ex:12: find_team
lib/ichor/fleet/runtime_view.ex:18: merge_display_teams
lib/ichor/fleet/runtime_view.ex:50: build_agent_lookup
lib/ichor/fleet/tmux_helpers.ex:10: tmux_args
lib/ichor/fleet/tmux_helpers.ex:18: capability_to_role
lib/ichor/fleet/tmux_helpers.ex:23: capabilities_for
lib/ichor/fleet/tmux_helpers.ex:29: add_permission_args
lib/ichor/fleet/runtime_query.ex:10: find_team_member
lib/ichor/fleet/runtime_query.ex:16: find_agent_entry
lib/ichor/fleet/runtime_query.ex:25: find_active_task
lib/ichor/fleet/runtime_query.ex:33: list_tasks_for_teams
lib/ichor/fleet/runtime_query.ex:41: format_team
lib/ichor/fleet/agent_process/registry.ex:8: build_initial_meta
lib/ichor/fleet/agent_process/registry.ex:33: fields_from_event
lib/ichor/fleet/agent_process/lifecycle.ex:10: schedule_liveness_check
lib/ichor/fleet/agent_process/lifecycle.ex:19: terminate_backend
lib/ichor/fleet/agent_process/lifecycle.ex:29: broadcast
lib/ichor/fleet/agent_process/mailbox.ex:10: apply_incoming_message
lib/ichor/fleet/agent_process/mailbox.ex:17: deliver_unread
lib/ichor/fleet/agent_process/mailbox.ex:22: route_message
lib/ichor/fleet/lifecycle/tmux_launcher.ex:9: create_session
lib/ichor/fleet/lifecycle/tmux_launcher.ex:14: create_window
lib/ichor/fleet/lifecycle/tmux_launcher.ex:19: kill_session
lib/ichor/fleet/lifecycle/tmux_launcher.ex:22: send_exit
lib/ichor/fleet/lifecycle/tmux_launcher.ex:28: list_sessions
lib/ichor/fleet/lifecycle/cleanup.ex:16: stop_agent
lib/ichor/fleet/lifecycle/cleanup.ex:32: kill_session
lib/ichor/fleet/lifecycle/cleanup.ex:35: cleanup_prompt_dir
lib/ichor/fleet/lifecycle/cleanup.ex:38: cleanup_orphaned_teams
lib/ichor/fleet/lifecycle/cleanup.ex:48: cleanup_orphaned_tmux_sessions
lib/ichor/fleet/lifecycle/cleanup.ex:58: trigger_gc
lib/ichor/fleet/lifecycle/tmux_script.ex:10: write_agent_files
lib/ichor/fleet/lifecycle/tmux_script.ex:23: cleanup_dir
lib/ichor/fleet/lifecycle/tmux_script.ex:32: render_script
lib/ichor/fleet/lifecycle/registration.ex:15: ensure_team
lib/ichor/fleet/lifecycle/registration.ex:25: register
lib/ichor/fleet/lifecycle/registration.ex:104: resolve_tmux_target
lib/ichor/fleet/lifecycle/agent_launch.ex:33: init_counter
lib/ichor/fleet/lifecycle/agent_launch.ex:40: spawn
lib/ichor/fleet/lifecycle/agent_launch.ex:50: spawn_local
lib/ichor/fleet/lifecycle/agent_launch.ex:69: stop
lib/ichor/fleet/lifecycle/agent_launch.ex:72: list_spawned
lib/ichor/fleet/lifecycle/team_spec.ex:21: new
lib/ichor/fleet/lifecycle/team_launch.ex:12: launch
lib/ichor/fleet/lifecycle/team_launch.ex:28: launch_into_existing_session
lib/ichor/fleet/lifecycle/agent_spec.ex:34: new
```

### Genesis modules

```
lib/ichor/genesis/mode_prompts.ex:11: mode_a_coordinator
lib/ichor/genesis/mode_prompts.ex:53: mode_a_architect
lib/ichor/genesis/mode_prompts.ex:88: mode_a_reviewer
lib/ichor/genesis/mode_prompts.ex:120: mode_b_coordinator
lib/ichor/genesis/mode_prompts.ex:160: mode_b_analyst
lib/ichor/genesis/mode_prompts.ex:185: mode_b_designer
lib/ichor/genesis/mode_prompts.ex:209: mode_c_coordinator
lib/ichor/genesis/mode_prompts.ex:245: mode_c_planner
lib/ichor/genesis/mode_prompts.ex:276: mode_c_architect
lib/ichor/genesis/dag_generator.ex:14: generate
lib/ichor/genesis/dag_generator.ex:27: to_jsonl_string
lib/ichor/genesis/mode_runner.ex:15: write_agent_scripts
lib/ichor/genesis/mode_runner.ex:43: create_session_with_agent
lib/ichor/genesis/mode_runner.ex:58: create_remaining_windows
lib/ichor/genesis/mode_runner.ex:74: register_agent
lib/ichor/genesis/mode_runner.ex:92: kill_session
lib/ichor/genesis/run_process.ex:34: via
lib/ichor/genesis/run_process.ex:37: lookup
lib/ichor/genesis/run_process.ex:45: list_all
lib/ichor/genesis/mode_spawner.ex:20: spawn_mode
lib/ichor/genesis/mode_spawner.ex:51: ensure_genesis_node
lib/ichor/genesis/mode_spawner.ex:152: load_project_brief
```

### Gateway modules

```
lib/ichor/gateway/topology_builder.ex:22: subscribe_to_session
lib/ichor/gateway/webhook_delivery.ex:26: changeset
lib/ichor/gateway/hitl_intervention_event.ex:25: changeset
lib/ichor/gateway/cron_job.ex:23: changeset
lib/ichor/gateway/schema_interceptor.ex:29: validate_and_enrich
lib/ichor/gateway/schema_interceptor.ex:40: build_violation_event
lib/ichor/gateway/router/delivery.ex:7: deliver
lib/ichor/gateway/router/audit.ex:10: record
lib/ichor/gateway/router/event_ingest.ex:11: ingest
lib/ichor/gateway/router/recipient_resolver.ex:10: resolve
```

### Memory modules

```
lib/ichor/memory_store/persistence.ex:10: load_from_disk
lib/ichor/memory_store/persistence.ex:16: load_jsonl
lib/ichor/memory_store/persistence.ex:30: flush_dirty
lib/ichor/memory_store/recall.ex:8: get
lib/ichor/memory_store/recall.ex:15: add
lib/ichor/memory_store/recall.ex:29: search
lib/ichor/memory_store/recall.ex:40: search_by_date
lib/ichor/memory_store/broadcast.ex:6: block_changed
lib/ichor/memory_store/broadcast.ex:10: agent_changed
lib/ichor/memory_store/blocks.ex:13: get
lib/ichor/memory_store/blocks.ex:20: list
lib/ichor/memory_store/blocks.ex:32: create
lib/ichor/memory_store/blocks.ex:38: create_many
lib/ichor/memory_store/blocks.ex:58: save_value
lib/ichor/memory_store/blocks.ex:67: delete
lib/ichor/memory_store/blocks.ex:81: resolve
lib/ichor/memory_store/blocks.ex:91: find_agent_block
lib/ichor/memory_store/blocks.ex:108: compile
lib/ichor/memory_store/blocks.ex:110: build
lib/ichor/memory_store/blocks.ex:123: attr
lib/ichor/memory_store/blocks.ex:125: maybe_put
lib/ichor/memory_store/archival.ex:10: get
lib/ichor/memory_store/archival.ex:17: count
lib/ichor/memory_store/archival.ex:36: for_search
lib/ichor/memory_store/archival.ex:47: insert
lib/ichor/memory_store/archival.ex:61: search
lib/ichor/memory_store/archival.ex:74: delete
lib/ichor/memory_store/archival.ex:80: list
lib/ichor/memory_store/archival.ex:91: filter_by_tags
```

### MES modules

```
lib/ichor/mes/team_lifecycle.ex:11: spawn_run
lib/ichor/mes/team_lifecycle.ex:30: spawn_corrective_agent
lib/ichor/mes/team_lifecycle.ex:42: kill_session
lib/ichor/mes/research_store.ex:15: search
lib/ichor/mes/research_store.ex:20: list_entities
lib/ichor/mes/research_store.ex:26: list_facts
lib/ichor/mes/research_store.ex:32: recent_episodes
lib/ichor/mes/research_store.ex:37: query
lib/ichor/mes/subsystem_loader.ex:16: compile_and_load
lib/ichor/mes/subsystem_scaffold.ex:13: scaffold
lib/ichor/mes/subsystem_scaffold.ex:24: derive_names
lib/ichor/mes/subsystem_scaffold.ex:36: subsystem_path
lib/ichor/mes/team_spec_builder.ex:15: build_team_spec
lib/ichor/mes/team_spec_builder.ex:38: build_corrective_team_spec
lib/ichor/mes/team_spec_builder.ex:66: session_name
lib/ichor/mes/team_spec_builder.ex:69: prompt_dir
lib/ichor/mes/team_spec_builder.ex:72: prompt_root_dir
lib/ichor/mes/run_process.ex:40: via
lib/ichor/mes/run_process.ex:43: lookup
lib/ichor/mes/run_process.ex:51: list_all
lib/ichor/mes/team_cleanup.ex:13: kill_session
lib/ichor/mes/team_cleanup.ex:21: cleanup_old_runs
lib/ichor/mes/team_cleanup.ex:28: cleanup_prompt_root_dir
lib/ichor/mes/team_cleanup.ex:38: cleanup_prompt_files
lib/ichor/mes/team_cleanup.ex:50: cleanup_orphaned_teams
lib/ichor/mes/team_cleanup.ex:70: active_team_names
lib/ichor/mes/team_cleanup.ex:77: orphaned_team_names
lib/ichor/mes/team_cleanup.ex:85: orphaned_sessions
lib/ichor/mes/team_prompts.ex:9: roster
lib/ichor/mes/team_prompts.ex:23: coordinator
lib/ichor/mes/team_prompts.ex:107: lead
lib/ichor/mes/team_prompts.ex:135: planner
lib/ichor/mes/team_prompts.ex:180: researcher_1
lib/ichor/mes/team_prompts.ex:340: researcher_2
lib/ichor/mes/team_prompts.ex:452: corrective
lib/ichor/mes/subsystem_scaffold/templates.ex:8: mix_exs
lib/ichor/mes/subsystem_scaffold/templates.ex:39: module_placeholder
lib/ichor/mes/subsystem_scaffold/templates.ex:78: formatter
lib/ichor/mes/subsystem_scaffold/templates.ex:87: gitignore
lib/ichor/mes/subsystem_scaffold/templates.ex:96: readme
lib/ichor/mes/subsystem_scaffold/templates.ex:121: integration
```

### Misc

```
lib/ichor/agent_watchdog/nudge_policy.ex:50: process_escalations
lib/ichor/architecture/boundary_audit.ex:28: print_report
lib/ichor/message_router/target.ex:15: resolve
lib/ichor/activity/event_analysis.ex:11: tool_analytics  (NOTE: has @doc but script flagged it)
```

---

## 3. Missing `@spec` on public functions (196 in ichor/)

This list covers only ichor/ (not ichor_web/ which has 680+ additional). Multi-clause functions are deduplicated to first occurrence only. `@impl true` callbacks are excluded.

### event_buffer.ex

```
lib/ichor/event_buffer.ex:29: ingest
lib/ichor/event_buffer.ex:46: list_events
lib/ichor/event_buffer.ex:53: latest_per_session
lib/ichor/event_buffer.ex:85: remove_session
lib/ichor/event_buffer.ex:91: tombstone_session
lib/ichor/event_buffer.ex:97: events_for_session
```

### memory_store.ex (domain delegator)

```
lib/ichor/memory_store.ex:44: create_block
lib/ichor/memory_store.ex:49: get_block
lib/ichor/memory_store.ex:54: update_block
lib/ichor/memory_store.ex:59: delete_block
lib/ichor/memory_store.ex:64: list_blocks
lib/ichor/memory_store.ex:75: create_agent
lib/ichor/memory_store.ex:80: get_agent
lib/ichor/memory_store.ex:85: attach_block
lib/ichor/memory_store.ex:90: detach_block
lib/ichor/memory_store.ex:95: list_agents
lib/ichor/memory_store.ex:103: read_core_memory
lib/ichor/memory_store.ex:111: compile_memory
lib/ichor/memory_store.ex:118: memory_replace
lib/ichor/memory_store.ex:123: memory_insert
lib/ichor/memory_store.ex:128: memory_rethink
lib/ichor/memory_store.ex:135: add_recall
lib/ichor/memory_store.ex:140: conversation_search
lib/ichor/memory_store.ex:145: conversation_search_date
lib/ichor/memory_store.ex:155: archival_memory_insert
lib/ichor/memory_store.ex:160: archival_memory_search
lib/ichor/memory_store.ex:165: archival_memory_delete
lib/ichor/memory_store.ex:170: archival_memory_list
```

### protocol_tracker.ex

```
lib/ichor/protocol_tracker.ex:29: track_mailbox_delivery
lib/ichor/protocol_tracker.ex:34: track_command_write
lib/ichor/protocol_tracker.ex:39: track_gateway_broadcast
```

### mesh/

```
lib/ichor/mesh/decision_log.ex:233: changeset
lib/ichor/mesh/decision_log.ex:247: major_version
lib/ichor/mesh/decision_log.ex:261: put_gateway_entropy_score
lib/ichor/mesh/decision_log.ex:273: from_json
lib/ichor/mesh/causal_dag.ex:34: insert
lib/ichor/mesh/causal_dag.ex:38: get_session_dag
lib/ichor/mesh/causal_dag.ex:42: get_children
lib/ichor/mesh/causal_dag.ex:46: signal_terminal
```

### tasks/

```
lib/ichor/tasks/board.ex:8: create_task
lib/ichor/tasks/board.ex:15: update_task
lib/ichor/tasks/board.ex:22: delete_task
lib/ichor/tasks/jsonl_store.ex:8: heal_task
lib/ichor/tasks/jsonl_store.ex:10: reassign_task
lib/ichor/tasks/jsonl_store.ex:19: claim_task
lib/ichor/tasks/jsonl_store.ex:32: update_task_status
lib/ichor/tasks/pipeline.ex:8: heal_task
lib/ichor/tasks/pipeline.ex:10: reassign_task
lib/ichor/tasks/pipeline.ex:13: claim_task
lib/ichor/tasks/pipeline.ex:15: update_task_status
lib/ichor/tasks/team_store.ex:10: create_task
lib/ichor/tasks/team_store.ex:37: update_task
lib/ichor/tasks/team_store.ex:61: get_task
lib/ichor/tasks/team_store.ex:71: list_tasks
lib/ichor/tasks/team_store.ex:86: delete_task
lib/ichor/tasks/team_store.ex:102: next_task_id
```

### tools/

```
lib/ichor/tools/genesis_formatter.ex:6: to_map
lib/ichor/tools/genesis_formatter.ex:19: summarize
lib/ichor/tools/genesis_formatter.ex:25: stringify
lib/ichor/tools/genesis_formatter.ex:29: split_csv
lib/ichor/tools/genesis_formatter.ex:38: parse_enum
lib/ichor/tools/genesis_formatter.ex:44: put_if
lib/ichor/tools/agent_control.ex:10: spawn
lib/ichor/tools/agent_control.ex:28: stop
lib/ichor/tools/agent_control.ex:40: pause
lib/ichor/tools/agent_control.ex:58: resume
```

### activity/

```
lib/ichor/activity/event_analysis.ex:11: tool_analytics
lib/ichor/activity/event_analysis.ex:56: timeline
lib/ichor/activity/event_analysis.ex:82: pair_tool_events
```

### dag/graph.ex (most function-rich non-spec'd module)

```
lib/ichor/dag/graph.ex:5: to_graph_node
lib/ichor/dag/graph.ex:41: waves
lib/ichor/dag/graph.ex:78: edges
lib/ichor/dag/graph.ex:82: dag
lib/ichor/dag/graph.ex:85: critical_path
lib/ichor/dag/graph.ex:151: pipeline_stats
lib/ichor/dag/graph.ex:163: available
lib/ichor/dag/graph.ex:174: stale_items
lib/ichor/dag/graph.ex:206: file_conflicts
```

### dag/actions.ex, runtime.ex, analysis.ex, projects.ex, health_report.ex

```
lib/ichor/dag/actions.ex:11: heal_task
lib/ichor/dag/actions.ex:18: reassign_task
lib/ichor/dag/actions.ex:25: claim_task
lib/ichor/dag/actions.ex:32: reset_all_stale
lib/ichor/dag/actions.ex:49: trigger_gc
lib/ichor/dag/prompts.ex:20: coordinator
lib/ichor/dag/prompts.ex:71: lead
lib/ichor/dag/prompts.ex:121: worker
lib/ichor/dag/runtime.ex:24: set_active_project
lib/ichor/dag/runtime.ex:27: add_project
lib/ichor/dag/runtime.ex:30: heal_task
lib/ichor/dag/runtime.ex:33: reassign_task
lib/ichor/dag/runtime.ex:36: reset_all_stale
lib/ichor/dag/runtime.ex:39: trigger_gc
lib/ichor/dag/runtime.ex:45: claim_task
lib/ichor/dag/analysis.ex:8: refresh_tasks
lib/ichor/dag/analysis.ex:43: parse_tasks_jsonl
lib/ichor/dag/analysis.ex:54: find_stale_tasks
lib/ichor/dag/discovery.ex:27: scan_archives
lib/ichor/dag/projects.ex:8: initial_state
lib/ichor/dag/projects.ex:20: set_active_project
lib/ichor/dag/projects.ex:28: add_project
lib/ichor/dag/projects.ex:41: refresh_discovered_projects
lib/ichor/dag/projects.ex:56: register_cwd
lib/ichor/dag/projects.ex:78: tasks_jsonl_path
lib/ichor/dag/projects.ex:85: tasks_jsonl_path_for_task
lib/ichor/dag/projects.ex:101: active_project_path
lib/ichor/dag/projects.ex:108: first_project_key
lib/ichor/dag/health_report.ex:21: parse_health_output
```

### signals/catalog/*_defs.ex

```
lib/ichor/signals/catalog/mes_defs.ex:4: definitions
lib/ichor/signals/catalog/gateway_agent_defs.ex:4: definitions
lib/ichor/signals/catalog/core_defs.ex:4: definitions
lib/ichor/signals/catalog/genesis_dag_defs.ex:4: definitions
lib/ichor/signals/catalog/team_monitoring_defs.ex:4: definitions
```

### memory_store/* sub-modules

```
lib/ichor/memory_store/persistence.ex:10: load_from_disk
lib/ichor/memory_store/persistence.ex:16: load_jsonl
lib/ichor/memory_store/persistence.ex:30: flush_dirty
lib/ichor/memory_store/recall.ex:8: get
lib/ichor/memory_store/recall.ex:15: add
lib/ichor/memory_store/recall.ex:29: search
lib/ichor/memory_store/recall.ex:40: search_by_date
lib/ichor/memory_store/broadcast.ex:6: block_changed
lib/ichor/memory_store/broadcast.ex:10: agent_changed
lib/ichor/memory_store/blocks.ex:13: get
lib/ichor/memory_store/blocks.ex:20: list
lib/ichor/memory_store/blocks.ex:32: create
lib/ichor/memory_store/blocks.ex:38: create_many
lib/ichor/memory_store/blocks.ex:58: save_value
lib/ichor/memory_store/blocks.ex:67: delete
lib/ichor/memory_store/blocks.ex:81: resolve
lib/ichor/memory_store/blocks.ex:91: find_agent_block
lib/ichor/memory_store/blocks.ex:108: compile
lib/ichor/memory_store/blocks.ex:110: build
lib/ichor/memory_store/blocks.ex:123: attr
lib/ichor/memory_store/blocks.ex:125: maybe_put
lib/ichor/memory_store/archival.ex:10: get
lib/ichor/memory_store/archival.ex:17: count
lib/ichor/memory_store/archival.ex:36: for_search
lib/ichor/memory_store/archival.ex:47: insert
lib/ichor/memory_store/archival.ex:61: search
lib/ichor/memory_store/archival.ex:74: delete
lib/ichor/memory_store/archival.ex:80: list
lib/ichor/memory_store/archival.ex:91: filter_by_tags
```

### fleet/ sub-modules

```
lib/ichor/fleet/runtime_view.ex:8: resolve_selected_team
lib/ichor/fleet/runtime_view.ex:12: find_team
lib/ichor/fleet/runtime_view.ex:18: merge_display_teams
lib/ichor/fleet/runtime_view.ex:50: build_agent_lookup
lib/ichor/fleet/runtime_query.ex:10: find_team_member
lib/ichor/fleet/runtime_query.ex:16: find_agent_entry
lib/ichor/fleet/runtime_query.ex:25: find_active_task
lib/ichor/fleet/runtime_query.ex:33: list_tasks_for_teams
lib/ichor/fleet/runtime_query.ex:41: format_team
lib/ichor/fleet/agent_process/registry.ex:8: build_initial_meta
lib/ichor/fleet/agent_process/registry.ex:33: fields_from_event
lib/ichor/fleet/agent_process/lifecycle.ex:10: schedule_liveness_check
lib/ichor/fleet/agent_process/lifecycle.ex:19: terminate_backend
lib/ichor/fleet/agent_process/lifecycle.ex:29: broadcast
lib/ichor/fleet/agent_process/mailbox.ex:10: apply_incoming_message
lib/ichor/fleet/agent_process/mailbox.ex:17: deliver_unread
lib/ichor/fleet/agent_process/mailbox.ex:22: route_message
lib/ichor/fleet/analysis/agent_health.ex:14: compute_agent_health
lib/ichor/fleet/analysis/agent_health.ex:35: calculate_failure_rate
lib/ichor/fleet/analysis/queries.ex:15: active_sessions
lib/ichor/fleet/analysis/queries.ex:47: topology
```

### genesis/ sub-modules

```
lib/ichor/genesis/mode_prompts.ex:11: mode_a_coordinator
lib/ichor/genesis/mode_prompts.ex:53: mode_a_architect
lib/ichor/genesis/mode_prompts.ex:88: mode_a_reviewer
lib/ichor/genesis/mode_prompts.ex:120: mode_b_coordinator
lib/ichor/genesis/mode_prompts.ex:160: mode_b_analyst
lib/ichor/genesis/mode_prompts.ex:185: mode_b_designer
lib/ichor/genesis/mode_prompts.ex:209: mode_c_coordinator
lib/ichor/genesis/mode_prompts.ex:245: mode_c_planner
lib/ichor/genesis/mode_prompts.ex:276: mode_c_architect
lib/ichor/genesis/mode_spawner.ex:152: load_project_brief
```

### gateway/ sub-modules

```
lib/ichor/gateway/topology_builder.ex:22: subscribe_to_session
lib/ichor/gateway/webhook_router.ex:25: enqueue
lib/ichor/gateway/webhook_router.ex:47: list_dead_letters
lib/ichor/gateway/webhook_router.ex:54: list_all_dead_letters
lib/ichor/gateway/webhook_router.ex:63: compute_signature
lib/ichor/gateway/webhook_router.ex:69: verify_signature
lib/ichor/gateway/webhook_delivery.ex:26: changeset
lib/ichor/gateway/hitl_intervention_event.ex:25: changeset
lib/ichor/gateway/heartbeat_manager.ex:21: record_heartbeat
lib/ichor/gateway/cron_job.ex:23: changeset
lib/ichor/gateway/router.ex:21: channels
lib/ichor/gateway/router.ex:31: broadcast
lib/ichor/gateway/router.ex:55: ingest
lib/ichor/gateway/envelope.ex:27: new
lib/ichor/gateway/cron_scheduler.ex:29: schedule_once
lib/ichor/gateway/cron_scheduler.ex:34: list_jobs
lib/ichor/gateway/cron_scheduler.ex:39: list_all_jobs
lib/ichor/gateway/channels/tmux.ex:65: capture_pane
lib/ichor/gateway/channels/tmux.ex:77: list_panes
lib/ichor/gateway/channels/tmux.ex:97: list_sessions
lib/ichor/gateway/channels/tmux.ex:111: run_command
lib/ichor/gateway/channels/tmux.ex:114: socket_args
lib/ichor/gateway/channels/ssh_tmux.ex:58: capture_pane
lib/ichor/gateway/channels/ssh_tmux.ex:69: list_sessions
```

---

## 4. Banner comments to remove (19)

The following files contain `# -- Label --` or `# --- Section ---` style decorative banners, which are banned per project rules. Use `@doc`, named functions, and module structure for organization instead.

```
lib/ichor_web/components/fleet_helpers.ex:7:    # -- Role classification --
lib/ichor_web/components/fleet_helpers.ex:51:   # -- Hierarchy sorting --
lib/ichor_web/components/fleet_helpers.ex:64:   # -- Chain of command --
lib/ichor_web/components/fleet_helpers.ex:91:   # -- Comms helpers --
lib/ichor_web/components/fleet_helpers.ex:159:  # -- Project grouping --
lib/ichor_web/live/dashboard_archon_handlers.ex:73:  # -- Private ---...
lib/ichor/control.ex:26:    # -- Fleet functions --
lib/ichor/control.ex:46:    # -- Workshop functions --
lib/ichor/agent_watchdog.ex:89:   # --- Crash detection ---...
lib/ichor/agent_watchdog.ex:198:  # --- Escalation ---...
lib/ichor/agent_watchdog.ex:312:  # --- Pane scanning ---...
lib/ichor/agent_watchdog.ex:401:  # --- Config / Timer ---...
lib/ichor/dag/validator.ex:49:    # --- private helpers ---
lib/ichor/gateway/entropy_tracker.ex:20:  # -- Public API --
lib/ichor/gateway/entropy_tracker.ex:62:  # -- GenServer Callbacks --
lib/ichor/gateway/entropy_tracker.ex:130: # -- Private Functions --
lib/ichor/gateway/hitl_relay.ex:15:   # --- Public API ---
lib/ichor/gateway/hitl_relay.ex:78:   # --- GenServer callbacks ---
lib/ichor/gateway/hitl_relay.ex:202:  # --- Private ---
```

**Affected files (5 unique):**
- `lib/ichor_web/components/fleet_helpers.ex` (5 banners)
- `lib/ichor_web/live/dashboard_archon_handlers.ex` (1 banner)
- `lib/ichor/control.ex` (2 banners)
- `lib/ichor/agent_watchdog.ex` (4 banners)
- `lib/ichor/dag/validator.ex` (1 banner)
- `lib/ichor/gateway/entropy_tracker.ex` (3 banners)
- `lib/ichor/gateway/hitl_relay.ex` (3 banners)

---

## 5. Missing `@enforce_keys` on structs (8)

Structs without `@enforce_keys` will silently accept `nil` for fields that should be required. Per project rules: "Structs are our contracts. We must be more strict."

```
lib/ichor/archon/memories_client.ex:57   -- Edge struct (uuid, fact, name, source, target, score, created_at)
lib/ichor/archon/memories_client.ex:69   -- Answer struct (answer, citations, context)
lib/ichor/dag/run_process.ex:29          -- %RunProcess{} (run_id, tmux_session, project_path)
lib/ichor/fleet/agent_process.ex:35      -- %AgentProcess{} (large struct, has @type t but no @enforce_keys)
lib/ichor/fleet/team_supervisor.ex:16    -- %TeamSupervisor{} (name, project, strategy, lead_id)
lib/ichor/genesis/run_process.ex:25      -- %RunProcess{} (run_id, mode, session, node_id)
lib/ichor/mes/run_process.ex:31          -- %RunProcess{} (run_id, team_name, session, deadline_passed)
lib/ichor/mesh/causal_dag.ex:16          -- %Node{} (inner module, trace_id and siblings)
```

**Already correct (have @enforce_keys):**
- `lib/ichor/archon/memories_client.ex` -- EpisodeSync and ChunkedMemory structs
- `lib/ichor/fleet/lifecycle/agent_spec.ex`
- `lib/ichor/fleet/lifecycle/team_spec.ex`
- `lib/ichor/gateway/envelope.ex`
- `lib/ichor/signals/stream_entry.ex`

---

## 6. Missing `@type t` on structs (5)

Structs without `@type t :: %__MODULE__{}` cannot be used in typespecs for other modules.

```
lib/ichor/dag/run_process.ex        -- %RunProcess{} has no @type t
lib/ichor/fleet/team_supervisor.ex  -- %TeamSupervisor{} has no @type t
lib/ichor/genesis/run_process.ex    -- %RunProcess{} has no @type t
lib/ichor/mes/run_process.ex        -- %RunProcess{} has no @type t
lib/ichor/mesh/causal_dag.ex        -- inner %Node{} struct has no @type t
```

**Note:** The `memories_client.ex` inner structs (Edge, Answer) also lack `@type t` but are nested sub-modules inside the client -- lower priority.

---

## Priority Triage

### Fix immediately (contract violations)

1. **`@enforce_keys` on 8 structs** -- these are silent contract holes. `%RunProcess{}` structs in dag/genesis/mes are runtime-critical.
2. **`@type t` on 5 struct files** -- blocks correct typespec coverage downstream.
3. **19 banner comments** -- these were previously cleaned (255 removed); they were re-introduced by agents and violate the standing ban.

### Fix in next pass (documentation gaps)

4. **`@moduledoc` on 12 ichor_web/ files** -- controllers and endpoint are missing documentation.
5. **`@spec` on 196 ichor/ public functions** -- prioritize domain modules (mes.ex, dag.ex, genesis.ex, observability.ex), then infrastructure (memory_store, event_buffer, protocol_tracker).
6. **`@doc` on 326 ichor/ public functions** -- apply to API-facing functions first (domain entry points, blueprint_state, workshop modules).
