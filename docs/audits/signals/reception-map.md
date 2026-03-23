# Signal Reception Map

Every subscribe and handle_info in the codebase. Exhaustive.

## Signals.subscribe calls

| # | File:Line | Topic/Signal | Scope | Type |
|---|-----------|-------------|-------|------|
| 1 | dashboard_live.ex:91 | ALL categories | category-level | mount |
| 2 | dashboard_session_control.ex:36 | `:gate_open` | scoped session_id | on pause |
| 3 | dashboard_session_control.ex:37 | `:gate_close` | scoped session_id | on pause |
| 4 | event_bridge.ex:33 | `:events` | category-level | init |
| 5 | event_bridge.ex:258 | `:dag_delta` | scoped session_id | dynamic per-session |
| 6 | team_spawn_handler.ex:21 | `:fleet` | category-level | init |
| 7 | spawn.ex:56 | `:team_spawn_ready` | scoped request_id | transient |
| 8 | spawn.ex:57 | `:team_spawn_failed` | scoped request_id | transient |
| 9 | team_watchdog.ex:31 | `:fleet` | category-level | init |
| 10 | team_watchdog.ex:32 | `:pipeline` | category-level | init (UNUSED) |
| 11 | team_watchdog.ex:33 | `:planning` | category-level | init (UNUSED) |
| 12 | team_watchdog.ex:34 | `:monitoring` | category-level | init (UNUSED) |
| 13 | agent_watchdog.ex:50 | `:events` | category-level | init |
| 14 | agent_watchdog.ex:51 | `:fleet` | category-level | init |
| 15 | entropy_tracker.ex:63 | `:events` | category-level | init |
| 16 | protocol_tracker.ex:39 | `:events` | category-level | init |
| 17 | protocol_tracker.ex:40 | `:heartbeat` | signal-level | init |
| 18 | event_stream.ex:150 | `:fleet` | category-level | init |
| 19 | agent_process.ex:188 | `:agent_event` | scoped agent id | init |
| 20 | session_cleanup_dispatcher.ex:26 | `:cleanup` | category-level | init |
| 21 | session_lifecycle.ex:33 | `:fleet` | category-level | init |
| 22 | research_ingestor.ex:28 | `:mes` | category-level | init |
| 23 | project_ingestor.ex:33 | `:messages` | category-level | init |
| 24 | completion_handler.ex:21 | `:pipeline` | category-level | init |
| 25 | run_cleanup_dispatcher.ex:26 | `:cleanup` | category-level | init |
| 26 | memories_bridge.ex:~60 | ALL categories | category-level | init |
| 27 | signal_manager.ex:~51 | ALL categories | category-level | init |
| 28 | buffer.ex:~37 | ALL categories | category-level | init |

## Raw PubSub.subscribe (bypassing Signals layer)

| File:Line | Topic | Purpose |
|-----------|-------|---------|
| dashboard_live.ex:132 | `"signals:feed"` | UI signal feed |
| dashboard_messaging_handlers.ex:88 | `"agent:#{session_id}"` | Per-agent mailbox |
| plugin_scaffold.ex:200 | `"plugin:#{app_name}"` | Plugin template (not live) |

## handle_info signal handlers

| # | File:Line | Signal | Action |
|---|-----------|--------|--------|
| 1 | agent_process.ex:291 | `:agent_event` (scoped) | Update registry projection |
| 2 | project_ingestor.ex:38 | `:message_delivered` | Ingest MES project from operator message |
| 3 | event_bridge.ex:39 | `:new_event` | Convert to DecisionLog, emit :decision_log, insert DAG node |
| 4 | event_bridge.ex:49 | `:dag_delta` | Fetch DAG, emit :topology_snapshot |
| 5 | memories_bridge.ex:79 | Any (non-ignored) | Buffer for Memories API flush |
| 6 | signal_manager.ex:66 | Any | Accumulate counts, latest, attention queue |
| 7 | team_watchdog.ex:39 | run_complete/terminated, team_disbanded, agent_stopped | Emit cleanup signals |
| 8 | agent_watchdog.ex:82 | `:new_event` | Update session activity, clear escalation |
| 9 | agent_watchdog.ex:89 | `:agent_stopped` | Drop session state |
| 10 | agent_watchdog.ex:95 | `:team_disbanded` | Drop team state |
| 11 | protocol_tracker.ex:46 | `:new_event` | Create trace record |
| 12 | protocol_tracker.ex:52 | `:heartbeat` | Compute stats, emit :protocol_update |
| 13 | buffer.ex:42 | Any | Insert ETS, broadcast "signals:feed" |
| 14 | session_cleanup_dispatcher.ex:31 | `:session_cleanup_needed` (disband) | Oban insert DisbandTeamWorker |
| 15 | session_cleanup_dispatcher.ex:40 | `:session_cleanup_needed` (kill) | Oban insert KillSessionWorker |
| 16 | session_lifecycle.ex:38 | `:session_started` | Spawn AgentProcess |
| 17 | session_lifecycle.ex:47 | `:session_ended` | Terminate AgentProcess |
| 18 | session_lifecycle.ex:57 | `:team_create_requested` | Create TeamSupervisor |
| 19 | session_lifecycle.ex:66 | `:team_delete_requested` | Disband team |
| 20 | runner.ex:226 | Any (configured) | Dispatch to run hook, check completion |
| 21 | research_ingestor.ex:33 | `:mes_project_created` | Ingest research to Memories API |
| 22 | run_cleanup_dispatcher.ex:31 | `:run_cleanup_needed` (archive) | Oban insert ArchiveRunWorker |
| 23 | run_cleanup_dispatcher.ex:40 | `:run_cleanup_needed` (reset_tasks) | Oban insert ResetRunTasksWorker |
| 24 | completion_handler.ex:26 | `:pipeline_completed` | Plugin compile+load, mark project |
| 25 | team_spawn_handler.ex:26 | `:team_spawn_requested` (scoped) | Launch team, emit ready/failed |
| 26 | entropy_tracker.ex:118 | `:new_event` | Score entropy, classify severity |
| 27 | event_stream.ex:210 | `:agent_stopped` | Tombstone session |

## Internal timers

| File:Line | Timer | Interval | Action |
|-----------|-------|----------|--------|
| agent_watchdog.ex:65 | `:beat` | 5s | Heartbeat, crash detect, escalation, pane scan |
| event_bridge.ex:64 | `:sweep` | 1h | Unsubscribe stale DAG sessions |
| causal_dag.ex:218 | `:sweep_stale_sessions` | 30m | Delete stale session ETS tables |
| hitl_relay.ex:147 | `:sweep` | periodic | Auto-release abandoned paused sessions |
| event_stream.ex:190 | `:check_heartbeats` | 30s | Evict stale agents, sweep tombstones |

## Receive-based (non-GenServer)

| File:Line | Signal | Pattern |
|-----------|--------|---------|
| spawn.ex:72-88 | `:team_spawn_ready` / `:team_spawn_failed` | Blocking receive with 30s timeout |
