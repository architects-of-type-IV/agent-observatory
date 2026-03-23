# Dead Code Report

All items confirmed with grep proof -- zero callers.

## Dead Modules (trash candidates)

| Module | File | Reason |
|--------|------|--------|
| `Ichor.Signals.TraceEvent` | `signals/trace_event.ex` | Never constructed. ProtocolTracker uses plain maps. |
| `Ichor.Infrastructure.ShellConfig` | `infrastructure/shell_config.ex` | Zero callers for any of 5 public functions |
| `Ichor.Factory.ResearchStore` | `factory/research_store.ex` | Only caller was trashed (dashboard_mes_research_handlers) |

## Dead Public Functions in signals/

| Function | File:Line | Why dead |
|----------|-----------|----------|
| `EventStream.publish_fact/2` | event_stream.ex:59 | Zero callers. Wrong emit shape. |
| `EventStream.latest_session_state/1` | event_stream.ex:75 | Zero callers. Heartbeat data nobody reads. |
| `EventStream handle_cast(:expire_tombstone)` | event_stream.ex:183 | Never dispatched. Sweep handles expiry directly. |
| `EntropyTracker.record_and_score/2` | entropy_tracker.ex:30 | Zero callers. Module is fully autonomous via handle_info. |
| `EntropyTracker.register_agent/2` | entropy_tracker.ex:39 | Zero callers. Vestigial. |
| `EntropyTracker.get_window/1` | entropy_tracker.ex:47 | Zero callers. "For testing" but no tests use it. |
| `EntropyTracker.reset/0` | entropy_tracker.ex:55 | Zero callers anywhere. |
| `SchemaInterceptor.build_violation_event/3` | schema_interceptor.ex:28 | Zero callers. Controller has no error branch. |
| `EscalationEngine.clear/2` | escalation_engine.ex:75 | Zero callers. Parent uses Map.pop inline. |
| `Bus.resolve/1` | bus.ex:83 | Public but only called from send/1 within same module. |

## Dead Public Functions outside signals/

| Function | File:Line | Why dead |
|----------|-----------|----------|
| `Queries.topology/3` | workshop/analysis/queries.ex:46 | Zero callers. Only active_sessions is used. |
| `AgentHealth.calculate_failure_rate/1` | workshop/analysis/agent_health.ex:37 | Public but only called internally. |
| `CausalDAG.reset/0` | mesh/causal_dag.ex:85 | Zero callers. |
| `CausalDAG.get_children/2` | mesh/causal_dag.ex:72 | Zero callers. |
| `CausalDAG.signal_terminal/1` | mesh/causal_dag.ex:78 | Zero callers. |
| `CronScheduler.list_jobs/1` | infrastructure/cron_scheduler.ex:50 | Zero callers. Only recover_jobs is used. |
| `CronScheduler.list_all_jobs/0` | infrastructure/cron_scheduler.ex:54 | Zero callers. |
| `MemoryStore` (11 dead functions) | memory_store.ex | `create_block`, `get_block`, `update_block`, `delete_block`, `list_blocks`, `attach_block`, `detach_block`, `compile_memory`, `data_dir`, `archival_memory_delete`, `archival_memory_list` |

## Write-Only State

| Item | File | Notes |
|------|------|-------|
| `ProtocolTracker.trace_count` | protocol_tracker.ex:42,86 | Incremented, never read |
| `ProtocolTracker command_queue` | protocol_tracker.ex:167 | Hardcoded `%{total_pending: 0}` |

## Never-Emitted Catalog Signals (~30+)

Signals defined in the catalog with renderers/subscribers wired but zero `Signals.emit` or `FromAsh` emission paths:

**High confidence (have subscribers/renderers that will never fire):**
- `:schema_violation` -- renderer exists, emitter missing
- `:capability_update` -- renderer exists, emitter missing
- `:gateway_audit` -- renderer exists, emitter missing
- `:registry_changed` -- subscriber in dashboard_info_handlers, emitter missing
- `:block_changed` -- renderer + narrater exist, emitter missing
- `:dashboard_command` -- no emitter
- `:watchdog_sweep` -- no emitter
- `:mailbox_message` -- no emitter

**MES/Pipeline cluster (likely removed during Runner refactor):**
- `:mes_agent_register_failed`, `:mes_agent_registered`, `:mes_agent_stopped`
- `:mes_cycle_timeout`, `:mes_maintenance_cleaned`, `:mes_maintenance_skipped`
- `:mes_prompts_written`, `:mes_quality_gate_*` (3 signals)
- `:mes_run_init`, `:mes_run_started`, `:mes_run_terminated`
- `:mes_scheduler_init`, `:mes_team_ready`, `:mes_team_spawn_failed`
- `:mes_tmux_*` (4 signals)

**Planning/Pipeline cluster:**
- `:pipeline_tmux_gone`, `:planning_run_init`, `:planning_run_terminated`
- `:planning_team_killed`, `:planning_tmux_gone`

**Monitoring:**
- `:agent_blocked`, `:agent_done` -- emitted dynamically via variable `signal_name` in agent_watchdog.ex:409
- `:gate_failed`, `:gate_passed` -- no emitter found
- `:agent_spawned` -- no emitter found
- `:task_created`, `:task_updated`, `:task_deleted` -- no emitter found (`:tasks_updated` IS emitted)
