---

# ADR-026 Findings: Signal as Projector Architecture Research

## Architecture Brief: Signal as Projector (ADR-026)

### What exists today

- **145 signals** in a hand-maintained `catalog.ex` across 7 groups
- **`Signals.emit/2`** builds a `%Message{}` envelope, broadcasts on `"signal:<category>"` and `"signal:<category>:<name>"` PubSub topics
- **12 subscriber GenServers** + LiveView subscribers consume signals via `handle_info(%Message{}, state)`
- **`MemoriesBridge`** is a 470-line GenServer with 40+ `narrate/2` clauses that pattern-match on flat maps it doesn't own, buffers per category, flushes every 30s via `MemoriesClient.ingest/2`
- **`%Ingest{}` struct** exists but is used as documentation only -- the client builds a plain map
- **1 embedded Ash resource** (`DecisionLog`) already exists as the pattern template
- **1 global Registry** (`Ichor.Registry`) with tagged-tuple keys (`{:agent, id}`, `{:team, name}`, etc.)
- **No `use Ichor.*` macros** exist yet -- this would be the first
- **No compile-time module discovery** pattern exists

### Critical constraints discovered

1. **Ash `@before_compile` struct generation** -- `%MySignal{}` is not available inside the resource module itself. Every Signal module needs a companion `helpers.ex` or must call `format/1` from outside the resource body.
2. **Embedded resources don't register in Ash Domains** -- catalog derivation cannot use `Ash.Domain.Info.resources/1`. Must use compile-time accumulation or runtime `function_exported?` scan.
3. **The `%Ingest{}` struct is not actually used by the client** -- it's a contract doc. The Memories projectors should be the first real consumers.
4. **`inspect()` poisoning** was the root cause of all Memories data quality issues. Signal modules owning `format/1` is the upstream fix with multiplicative downstream effect.
5. **Accumulation is stateful and local** -- each Memories projector decides independently when it has enough content to emit an `%Ingest{}`. This is a GenServer concern, not a pure function concern.

### Design evolution (5 iterations, user-rejected 4)

1. **Narrator module** -- rejected: "name by shape, not job"
2. **Content module** -- rejected: "data owns its own formatting"
3. **Episode struct** -- rejected: "Observatory doesn't own 'Episode'. Name it `Ingest`"
4. **Accumulation gap** -- "who decides WHEN to send? That's stateful"
5. **Signal as Projector** -- accepted: each signal IS a projector process

### What needs to be built

| Component | Description |
|---|---|
| `use Ichor.Signal` macro | Injects GenServer, PubSub subscribe in `init/1`, `handle_signal/2` callback, compile-time registration |
| Signal DSL | `signal do subscribe :gateway; publish :decision_log end` |
| Compile-time catalog | Replaces hand-maintained `catalog.ex` with derived module list |
| `Ichor.Signals.Supervisor` | DynamicSupervisor for all Signal GenServers |
| Registry keys | `{:signal, module_name}` convention in `Ichor.Registry` |
| 4 Memories projectors | `Memories.Gateway`, `.Fleet`, `.Mesh`, `.Agent` (~30-50 lines each) |
| `format/1` on existing signals | Starting with `DecisionLog` (already has `Helpers` module) |
| Migration shim | New signals coexist with old catalog during incremental migration |

### Supervision tree addition

```
Ichor.RuntimeSupervisor (existing)
  ├── ... (existing children)
  └── Ichor.Signals.ProjectorSupervisor (new, DynamicSupervisor)
        ├── Ichor.Signals.Memories.Gateway
        ├── Ichor.Signals.Memories.Fleet
        ├── Ichor.Signals.Memories.Mesh
        └── Ichor.Signals.Memories.Agent
```

### Data flow (new)

```
Raw PubSub event
  → Signal GenServer (handle_info matches %Message{})
  → handle_signal/2 callback (user-defined projection)
  → builds typed Ash embedded struct
  → publishes struct on "signal:<publish_name>"
  → downstream Memories projectors receive typed structs
  → accumulate, threshold check
  → builds %Ingest{} with format/1 from source Signal
  → Task.start(MemoriesClient, :ingest, [...])
```

---

## Signal Inventory

### Category: `:fleet` (22 signals)

| Signal | Dynamic | Keys |
|---|---|---|
| `agent_started` | | session_id, name, role, team |
| `agent_paused` | | session_id, name |
| `agent_resumed` | | session_id, name |
| `agent_stopped` | | session_id, name, reason |
| `agent_evicted` | | session_id |
| `agent_reaped` | | session_id |
| `agent_discovered` | | session_id |
| `agent_tmux_gone` | | agent_id, name, tmux |
| `team_created` | | name, project, strategy |
| `team_disbanded` | | team_name |
| `team_spawn_requested` | dynamic | team_name, spec, source |
| `team_spawn_started` | dynamic | team_name, agent_count, source |
| `team_spawn_ready` | dynamic | session, team_name, agent_count, source |
| `team_spawn_failed` | dynamic | team_name, reason, source |
| `team_create_requested` | | team_name |
| `team_delete_requested` | | team_name |
| `session_started` | | session_id, tmux_session, cwd, model, os_pid |
| `session_ended` | | session_id, status |
| `run_complete` | | kind, run_id, session |
| `run_terminated` | | kind, run_id, session |
| `hosts_changed` | | |
| `fleet_changed` | | agent_id |

### Category: `:gateway` (13 signals)

| Signal | Dynamic | Keys |
|---|---|---|
| `decision_log` | | log |
| `schema_violation` | | event_map |
| `node_state_update` | | agent_id, state |
| `entropy_alert` | | session_id, entropy_score |
| `topology_snapshot` | | nodes, edges |
| `capability_update` | | state_map |
| `dead_letter` | | delivery |
| `webhook_delivery_enqueued` | | delivery_id, agent_id, target_url, status, attempt_count |
| `webhook_delivery_delivered` | | delivery_id, agent_id, target_url, status, attempt_count |
| `gateway_audit` | | envelope_id, channel |
| `mesh_pause` | | initiated_by |
| `cron_job_scheduled` | | job_id, agent_id, next_fire_at |
| `cron_job_rescheduled` | | job_id, agent_id, next_fire_at |

### Category: `:agent` (12 signals)

| Signal | Dynamic | Keys |
|---|---|---|
| `agent_crashed` | | session_id, team_name |
| `nudge_warning` | | session_id, agent_name, level |
| `nudge_sent` | | session_id, agent_name, level |
| `nudge_escalated` | | session_id, agent_name, level |
| `nudge_zombie` | | session_id, agent_name, level |
| `agent_spawned` | | session_id, name, capability |
| `agent_event` | dynamic | event |
| `agent_message_intercepted` | dynamic | from, to, content, type |
| `terminal_output` | dynamic | session_id, output |
| `mailbox_message` | dynamic | message |
| `agent_instructions` | dynamic | agent_class, instructions |
| `scheduled_job` | dynamic | agent_id, payload |

### Category: `:hitl` (6 signals)

| Signal | Dynamic | Keys |
|---|---|---|
| `gate_open` | dynamic | session_id |
| `gate_close` | dynamic | session_id |
| `hitl_auto_released` | | session_id |
| `hitl_operator_approved` | | session_id |
| `hitl_operator_rejected` | | session_id |
| `hitl_intervention_recorded` | | event_id, session_id, agent_id, operator_id, action, details |

### Category: `:team` (4 signals)

| Signal | Dynamic | Keys |
|---|---|---|
| `task_created` | dynamic | task |
| `task_updated` | dynamic | task |
| `task_deleted` | dynamic | task_id |
| `tasks_updated` | | team_name |

### Category: `:monitoring` (6 signals)

| Signal | Dynamic | Keys |
|---|---|---|
| `protocol_update` | | stats_map |
| `gate_passed` | | session_id, task_id |
| `gate_failed` | | session_id, task_id, output |
| `agent_done` | | session_id, summary |
| `agent_blocked` | | session_id, reason |
| `watchdog_sweep` | | orphaned_count |

### Category: `:system` (5 signals)

| Signal | Dynamic | Keys |
|---|---|---|
| `heartbeat` | | count |
| `registry_changed` | | |
| `dashboard_command` | | command |
| `settings_project_created` | | project_id, name, is_active |
| `settings_project_updated` | | project_id, name, is_active |
| `settings_project_destroyed` | | project_id, name, is_active |

### Category: `:events` (1 signal)

| Signal | Dynamic | Keys |
|---|---|---|
| `new_event` | | event |

### Category: `:messages` (1 signal)

| Signal | Dynamic | Keys |
|---|---|---|
| `message_delivered` | | agent_id, msg_map |

### Category: `:memory` (2 signals)

| Signal | Dynamic | Keys |
|---|---|---|
| `block_changed` | | block_id, label |
| `memory_changed` | dynamic | agent_name, event |

### Category: `:mesh` (1 signal)

| Signal | Dynamic | Keys |
|---|---|---|
| `dag_delta` | dynamic | session_id, added_nodes |

### Category: `:cleanup` (2 signals)

| Signal | Dynamic | Keys |
|---|---|---|
| `run_cleanup_needed` | | run_id, action |
| `session_cleanup_needed` | | session, action |

### Category: `:mes` (35 signals)

| Signal | Dynamic | Keys |
|---|---|---|
| `mes_scheduler_init` | | paused |
| `mes_scheduler_paused` | | tick |
| `mes_scheduler_resumed` | | tick |
| `mes_tick` | | tick, active_runs |
| `mes_cycle_started` | | run_id, team_name |
| `mes_cycle_skipped` | | tick, active_runs |
| `mes_cycle_failed` | | run_id, reason |
| `mes_cycle_timeout` | | run_id, team_name |
| `mes_run_init` | | run_id, team_name |
| `mes_run_started` | | run_id, session |
| `mes_run_terminated` | | run_id |
| `mes_maintenance_init` | | monitored |
| `mes_maintenance_cleaned` | | run_id, trigger |
| `mes_maintenance_error` | | run_id, reason |
| `mes_maintenance_skipped` | | run_id, reason |
| `mes_prompts_written` | | run_id, agent_count |
| `mes_tmux_spawning` | | session, agent_name, command, tmux_args |
| `mes_tmux_session_created` | | session, agent_name |
| `mes_tmux_spawn_failed` | | session, output, exit_code |
| `mes_tmux_window_created` | | session, agent_name |
| `mes_team_ready` | | session, agent_count |
| `mes_team_killed` | | session |
| `mes_agent_registered` | | agent_name, session |
| `mes_agent_register_failed` | | agent_name, reason |
| `mes_team_spawn_failed` | | session, reason |
| `mes_operator_ensured` | | status |
| `mes_cleanup` | | target |
| `mes_project_created` | | project_id, title, run_id |
| `mes_project_picked_up` | | project_id, session_id |
| `mes_plugin_loaded` | | project_id, plugin, modules |
| `mes_quality_gate_passed` | | run_id, gate, session_id |
| `mes_quality_gate_failed` | | run_id, gate, session_id, reason |
| `mes_quality_gate_escalated` | | run_id, gate, failure_count |
| `mes_agent_stopped` | | agent_id, role, team, reason |
| `mes_research_ingested` | | run_id, project_id, episode_id |
| `mes_research_ingest_failed` | | run_id, reason |
| `mes_project_compiled` | | project_id, title |
| `mes_project_failed` | | project_id, title |
| `mes_plugin_compile_failed` | | run_id, project_id, reason |
| `mes_output_unhandled` | | run_id, project_id, output_kind |
| `mes_pipeline_generated` | | project_id |
| `mes_pipeline_launched` | | project_id, session |
| `mes_corrective_agent_spawned` | | run_id, session, attempt |
| `mes_corrective_agent_failed` | | run_id, session, reason |

### Category: `:planning` (11 signals)

| Signal | Dynamic | Keys |
|---|---|---|
| `planning_team_ready` | | session, mode, project_id, agent_count |
| `planning_team_spawn_failed` | | session, reason |
| `planning_team_killed` | | session |
| `planning_run_init` | | run_id, mode, session |
| `planning_tmux_gone` | | run_id, session |
| `planning_run_complete` | | run_id, mode, session, delivered_by |
| `planning_run_terminated` | | run_id, mode |
| `project_created` | | id, project_id, title, type |
| `project_advanced` | | id, project_id, title, type |
| `project_artifact_created` | | project_id |
| `project_roadmap_item_created` | | project_id |

### Category: `:pipeline` (12 signals)

| Signal | Dynamic | Keys |
|---|---|---|
| `pipeline_created` | | run_id, source, label, task_count |
| `pipeline_ready` | | run_id, session, project_id |
| `pipeline_completed` | | run_id, label |
| `pipeline_task_claimed` | | run_id, task_id, external_id, owner, wave |
| `pipeline_task_completed` | | run_id, task_id, external_id, owner |
| `pipeline_task_failed` | | run_id, task_id, external_id, notes |
| `pipeline_task_reset` | | run_id, task_id, external_id |
| `pipeline_tmux_gone` | | run_id, session |
| `pipeline_health_report` | | run_id, healthy, issue_count |
| `pipeline_status` | | state_map |
| `pipeline_archived` | | run_id, label, reason |
| `pipeline_reconciled` | | pipeline_id, run_id, action |

### Summary: 145 signals, 11 categories, 14 dynamic

---

## PubSub Topic Map

### Signal Topics (via `Ichor.Signals.Topics`)

All built by `topics.ex` -- no raw strings allowed outside this module.

### Category-level topics (`"signal:<category>"`)

| Topic | Subscribers |
|---|---|
| `signal:fleet` | SessionLifecycle, AgentWatchdog, EventStream, TeamWatchdog, TeamSpawnHandler, Buffer, DashboardLive, MemoriesBridge |
| `signal:gateway` | Buffer, DashboardLive, MemoriesBridge |
| `signal:agent` | Buffer, DashboardLive, MemoriesBridge |
| `signal:hitl` | Buffer, DashboardLive, MemoriesBridge |
| `signal:team` | Buffer, DashboardLive, MemoriesBridge |
| `signal:monitoring` | TeamWatchdog, Buffer, DashboardLive, MemoriesBridge |
| `signal:system` | Buffer, DashboardLive, MemoriesBridge |
| `signal:events` | AgentWatchdog, EntropyTracker, ProtocolTracker, EventBridge, Buffer, DashboardLive, MemoriesBridge |
| `signal:messages` | Buffer, DashboardLive, MemoriesBridge |
| `signal:memory` | Buffer, DashboardLive, MemoriesBridge |
| `signal:mesh` | Buffer, DashboardLive, MemoriesBridge |
| `signal:cleanup` | SessionCleanupDispatcher, RunCleanupDispatcher, Buffer, DashboardLive, MemoriesBridge |
| `signal:mes` | Buffer, DashboardLive, MemoriesBridge |
| `signal:planning` | TeamWatchdog, Buffer, DashboardLive, MemoriesBridge |
| `signal:pipeline` | TeamWatchdog, Buffer, DashboardLive, MemoriesBridge |
| `signal:heartbeat` | ProtocolTracker, Buffer, DashboardLive |

**16 category topics.**

### Per-signal static topics (`"signal:<category>:<name>"`)

Every static signal (131 of 145) gets a dedicated topic. These are broadcast on alongside the category topic. Examples:

- `signal:fleet:agent_started`
- `signal:fleet:session_ended`
- `signal:gateway:decision_log`
- `signal:gateway:dead_letter`
- `signal:mes:mes_cycle_started`
- etc.

**131 static signal topics.** Currently no subscriber uses per-signal topics -- all subscribe at category level.

### Scoped dynamic topics (`"signal:<category>:<name>:<scope_id>"`)

14 dynamic signals, each instantiated per scope_id at runtime:

| Pattern | Example |
|---|---|
| `signal:fleet:team_spawn_requested:<scope_id>` | `signal:fleet:team_spawn_requested:team-alpha` |
| `signal:fleet:team_spawn_started:<scope_id>` | |
| `signal:fleet:team_spawn_ready:<scope_id>` | |
| `signal:fleet:team_spawn_failed:<scope_id>` | |
| `signal:team:task_created:<scope_id>` | `signal:team:task_created:mes-abc123` |
| `signal:team:task_updated:<scope_id>` | |
| `signal:team:task_deleted:<scope_id>` | |
| `signal:agent:agent_event:<scope_id>` | `signal:agent:agent_event:agent-1` |
| `signal:agent:agent_message_intercepted:<scope_id>` | |
| `signal:agent:terminal_output:<scope_id>` | |
| `signal:agent:mailbox_message:<scope_id>` | |
| `signal:agent:agent_instructions:<scope_id>` | |
| `signal:agent:scheduled_job:<scope_id>` | |
| `signal:hitl:gate_open:<scope_id>` | `signal:hitl:gate_open:ses-xyz` |
| `signal:hitl:gate_close:<scope_id>` | |
| `signal:mesh:dag_delta:<scope_id>` | `signal:mesh:dag_delta:ses-xyz` |
| `signal:memory:memory_changed:<scope_id>` | |

**14 dynamic topic patterns** (unbounded instances at runtime).

### Raw PubSub Topics (outside Topics module)

| Topic | Producer | Consumer |
|---|---|---|
| `signals:feed` | Buffer (re-broadcasts every signal with sequence number) | DashboardLive |
| `agent:<session_id>` | DashboardMessagingHandlers (send) | DashboardMessagingHandlers (receive per-agent mailbox) |
| `plugin:<app_name>` | PluginScaffold | (no current consumer found) |

**3 raw topic patterns.**

### Topic Summary

| Type | Count |
|---|---|
| Category topics | 16 |
| Static per-signal topics | 131 |
| Dynamic topic patterns | 14 (unbounded instances) |
| Raw non-signal topics | 3 |
| **Total patterns** | **164** |

The key insight for ADR-026: **all current subscribers use category-level topics only**. The 131 per-signal static topics are broadcast but nobody subscribes to them individually. The new projectors would subscribe at category level too, matching the existing pattern.

---

## Subscriber Dispatch Map

### 1. SessionLifecycle (`:fleet`)

| Signal | Action |
|---|---|
| `:session_started` | If not already alive: `FleetSupervisor.spawn_agent(opts)` with role, tmux_session, cwd, model, os_pid |
| `:session_ended` | `AgentProcess.update_fields(sid, %{status: :ended})` then `FleetSupervisor.terminate_agent(sid)` |
| `:team_create_requested` | If team doesn't exist: `FleetSupervisor.create_team(name: team_name)` |
| `:team_delete_requested` | `FleetSupervisor.disband_team(team_name)` |
| _catch-all_ | no-op |

### 2. SessionCleanupDispatcher (`:cleanup`)

| Signal | Action |
|---|---|
| `:session_cleanup_needed` action `:disband` | `Oban.insert(DisbandTeamWorker)` unique per session/60s |
| `:session_cleanup_needed` action `:kill` | `Oban.insert(KillSessionWorker)` unique per session/60s |
| _catch-all_ | no-op |

### 3. RunCleanupDispatcher (`:cleanup`)

| Signal | Action |
|---|---|
| `:run_cleanup_needed` action `:archive` | `Oban.insert(ArchiveRunWorker)` unique per run_id/60s |
| `:run_cleanup_needed` action `:reset_tasks` | `Oban.insert(ResetRunTasksWorker)` unique per run_id/60s |
| _catch-all_ | no-op |

### 4. Buffer (all categories)

| Signal | Action |
|---|---|
| Any `%Message{}` | Increment seq, ETS insert `{seq, sig}`, evict if >200, PubSub broadcast `{:signal, seq, sig}` on `"signals:feed"` |

### 5. AgentWatchdog (`:events`, `:fleet`)

| Signal | Action |
|---|---|
| `:new_event` | Update `last_event_at` for session. On SessionStart: upsert session. On SessionEnd: delete session. Clear escalation if active (level >= 2 triggers `HITLRelay.unpause`). |
| `:agent_stopped` | Drop all state for session (sessions, escalations, captures, signals maps) |
| `:team_disbanded` | Drop state for all sessions matching team name |
| `:beat` (5s timer) | Emit `:heartbeat`. Detect crashes (>120s stale + not alive): reassign tasks to pending, emit `:agent_crashed`, write Inbox. Run escalation check: level 0 = emit `:nudge_warning`, level 1 = send nudge via Bus + emit `:nudge_sent`, level 2 = `HITLRelay.pause` + emit `:nudge_escalated`, level 3 = emit `:nudge_zombie`. Scan all tmux panes for DONE/BLOCKED patterns. |

### 6. EntropyTracker (`:events`)

| Signal | Action |
|---|---|
| `:new_event` | Extract session_id + tool_name. Slide 5-event window. Score = unique/total. < 0.25 = `:loop` (emit `:entropy_alert` + `:node_state_update` alert), < 0.50 = `:warning` (emit `:node_state_update` blocked), else `:normal` (emit recovery if prior was degraded). |
| _catch-all_ | no-op |

### 7. ProtocolTracker (`:events`, `:heartbeat`)

| Signal | Action |
|---|---|
| `:new_event` | Check if `{hook_event_type, tool_name}` matches trace types (SendMessage, TeamCreate, SubagentStart). If yes: build trace struct, insert ETS, evict if >200. |
| `:heartbeat` | Compute stats from ETS (count, group by type), emit `:protocol_update` |
| _catch-all_ | no-op |

### 8. EventStream (`:fleet`)

| Signal | Action |
|---|---|
| `:agent_stopped` | Tombstone session in ETS (monotonic timestamp) |
| `:check_heartbeats` (30s timer) | Find sessions >90s stale, emit `:agent_evicted` for each, drop from state. Sweep expired tombstones (>30s). |
| _catch-all_ | no-op |

### 9. TeamWatchdog (`:fleet`, `:pipeline`, `:planning`, `:monitoring`)

| Signal | Action |
|---|---|
| `:run_complete` | Add to `completed_runs`. For pipeline: emit `:run_cleanup_needed` (archive + reset_tasks) + `:session_cleanup_needed` (disband + kill) + Inbox notify. For planning/mes: disband + kill + notify. |
| `:run_terminated` | If already completed: no-op. Otherwise same cleanup chain as `:run_complete`. |
| `:team_disbanded` | If pipeline team disbanded without completion: Inbox notify operator. |
| `:agent_stopped` (coordinator/lead role) | If pipeline agent: Inbox notify "may be headless". |
| _catch-all_ | no-op |

### 10. EventBridge (`:events`, scoped `:dag_delta`)

| Signal | Action |
|---|---|
| `:new_event` | Build `%DecisionLog{}` from event, emit `:decision_log`. If valid IDs: build `%CausalDAG.Node{}`, `CausalDAG.insert(session_id, node)`. Subscribe to `:dag_delta` for new sessions. |
| `:dag_delta` | Get session DAG, build topology (nodes + edges), emit `:topology_snapshot` |
| `:sweep` (1h timer) | Unsubscribe from sessions >2h stale, drop state |
| _catch-all_ | no-op |

### 11. TeamSpawnHandler (`:fleet`)

| Signal | Action |
|---|---|
| `:team_spawn_requested` | Emit `:team_spawn_started`. Call `TeamLaunch.launch(spec)`. On success: emit `:team_spawn_ready`. On failure: emit `:team_spawn_failed`. |
| _catch-all_ | no-op |

### 12. MemoriesBridge (all categories)

| Signal | Action |
|---|---|
| Any `%Message{}` NOT in ignored list | Buffer signal under its category domain |
| Ignored (`:heartbeat`, `:terminal_output`, `:protocol_update`, `:pipeline_status`, `:topology_snapshot`, `:registry_changed`) | Drop silently |
| `:flush` (30s timer) | For each category buffer: narrate all signals to prose, check >= 80 chars unique, call `MemoriesClient.ingest/2` with space `"project:ichor:#{category}"` + extraction instructions |

### 13. DashboardLive + InfoHandlers (all categories + `"signals:feed"`)

| Signal | Action |
|---|---|
| `{:signal, seq, msg}` from feed | If not paused and passes filter: `stream_insert` to `:signals` stream (prepend, limit 200) |
| `:new_event` | Prepend to `@events` (cap 500), update `@now`, maybe refresh archon, schedule recompute |
| `:tasks_updated` | Schedule recompute |
| `:agent_crashed` | Handle crash notification, schedule recompute |
| `:agent_spawned` | Schedule recompute |
| `:agent_stopped` | Schedule recompute |
| `:registry_changed` | Schedule recompute |
| `:fleet_changed` | Schedule recompute |
| `:heartbeat` (with tmux panels) | Refresh all tmux panel captures |
| `:heartbeat` (no panels) | no-op |
| `:mailbox_message` | Delegate to messaging handler |
| `:pipeline_status` | Merge into `@pipeline_state`, maybe refresh archon |
| `:protocol_update` | Assign `@protocol_stats`, maybe refresh archon |
| `:terminal_output` | If slideout open for same session: update `@slideout_terminal` |
| `:gate_open` / `:gate_close` | Refresh `@paused_sessions` from `HITLRelay.paused_sessions()` |
| Nudge signals (warning/sent/escalated/zombie) | Maybe refresh archon only |
| `:gate_passed` / `:gate_failed` | Maybe refresh archon only |
| Gateway signals (decision_log, schema_violation, etc.) | Maybe refresh archon only |
| `:mes_project_created` | Reload `@mes_projects` |
| `:mes_scheduler_paused/resumed`, `:mes_cycle_started` | Reload `@mes_scheduler_status` |
| `:mes_plugin_loaded` | Reload `@mes_projects` |
| MES lifecycle signals (timeout, picked_up, research_*) | Maybe refresh archon only |
| Planning signals (artifact_created, team_ready, run_complete, team_killed) | Reload `@planning_project` if one is selected |
| _catch-all_ `%Message{}` | Maybe refresh archon only |

**Recompute** = 6 parallel Ash queries (sessions, teams, board, pipeline state, etc.), debounced at 100ms so rapid signals coalesce into one recompute.

---

## External Context: Memories Session Forensics (2026-03-24)

### Design Evolution: Narrator to Signal as Projector

The design went through five distinct iterations, each rejected by the user with a pointed question that drove toward a more principled architecture.

**Iteration 1 -- Narrator Module**
A `Narrator` module with `narrate/1` clauses per signal type. Rejected because: "The module has a job (narrator) not a shape. It will bloat." Key lesson: name modules by what they ARE (a shape, a boundary), not what they DO (narrate, process, handle).

**Iteration 2 -- Content Module**
Renamed to `Content` as a signal-to-text converter. Rejected because: "This is just a mediator. Who owns the formatting of a DecisionLog? Not a Content module." Key lesson: **data owns its own formatting**. A separate formatter module creates silent coupling -- when the source struct changes, the formatter breaks without a compile error.

**Iteration 3 -- Episode Struct**
Proposed `%Episode{}` matching the Memories API shape. Rejected with: "Why do you call it Episode? Does Observatory own the concept of an Episode?" Key lesson: **API shape dictates the struct name, not domain terms.** Observatory is a producer sending data to Memories; it doesn't own the "episode" concept. The struct should be named after the operation it performs in the API context: `%Ingest{}`.

**Iteration 4 -- The Accumulation Gap**
The user surfaced a fundamental design gap: "How do we know WHEN to send an Ingest? Who accumulates? Who decides threshold?" This is a stateful accumulation question with no answer in the previous designs. The user introduced the concept of a **Projector** -- a process that subscribes to PubSub topics, projects incoming events into typed structs, and publishes the result downstream.

**Iteration 5 -- Signal as Projector (Final Design)**
The user's final framing: "What if a Signal IS a Projector? Each signal module subscribes and projects."

Key properties:
- Each Signal module uses `use Ichor.Signal` macro
- The macro injects a supervised GenServer via `DynamicSupervisor + Registry`
- Signal subscribes to PubSub topics at `init/1`
- Signal projects raw events into its own struct via `handle_signal/2` callback
- Signal publishes the projected struct as a new typed signal downstream
- Signals compose -- a Memories projector subscribes to domain Signals

### Root Cause: `inspect()` Poisoning

`MemoriesBridge.narrate/2` called `inspect()` on 40+ signal types before sending content to Memories. Every episode contained raw Elixir struct syntax. The LLM entity extractor then treated Elixir module names, struct keys, and interpolated atoms as entities. This was identified as the root cause of all data quality issues.

### Rich Data Being Wasted

The richest signal, `DecisionLog`, carries six categories of structured data: `meta` (timestamp, agent role, session_id), `identity` (agent_name, team, fleet context), `cognition` (intent, reasoning, tools considered), `action` (tool called, arguments, result), `state_delta` (what changed in agent state), and `control` (escalation, handoff decisions). All of this was lost to `inspect()` output.

### Ranked Improvement Priorities

1. Fix Observatory input quality -- sending `inspect()` output poisons every downstream step; upstream fix has multiplicative effect
2. Wire entity attributes -- `Prompts.extract_entity_attributes/1` exists and works; the `attributes` column is `{}` for every entity
3. Embedding-based deduplication -- near-duplicates survive current string-match dedup
4. Per-space `extraction_instructions` -- the field is wired end-to-end; Observatory needs to send appropriate instructions per space
5. Entity salience scoring -- too many low-signal entities extracted

---

## External Context: Memories Tuning Session (2026-03-23)

### Data Quality Observations

**Input quality (client-side, Observatory):**
- The Observatory was sending raw Elixir `inspect()` output of structs as episode content
- All episodes were sent as `type=text, source=system`, which hits the general-purpose text extraction prompt

**Entity extraction noise:**
- Signal/event type names extracted as entities: `Signal Agent_event`, `Signal dag_delta`, `Signal fleet_changed`
- Elixir module names extracted as entities: `Ichor.Mesh.DecisionLog` classified as "document"
- Session IDs embedded in entity names: `Mes-93d47093`, `Mes-93d47093-lead`
- Boolean flags extracted as entities: `Session_cleanup_needed`
- Actions extracted as entities: `Gateway routing decision`
- Module docstrings extracted: `SignalCron -- Wall-Clock Signal Emitter`

**Entity resolution / deduplication failures:**
- Near-duplicates not merging: `ICHOR IV` vs `ICHOR IV control plane`, `Observatory` vs `Kardashev Observatory`
- Duplicate nodes in FalkorDB

**Fact quality:**
- Vague predicates: `OCCURRED`, `RECEIVED`, `ASSOCIATED_WITH`
- Semantically wrong facts: `ICHOR IV --[CONTROLS]--> Kardashev Observatory`

**Communities: 0**
- `CommunityMaintenanceJob` ran successfully but produced 0 communities because `@min_community_size 3` filters everything out
- Root cause: entity graph too fragmented from noisy extraction

### Technical Changes Made to Memories

**`extraction_instructions` field wired end-to-end:**
- New attribute on `episodes` table (nullable string, persisted per episode)
- Added to `:ingest` action and `:create_episode` accept list
- `LoadContext` step exposes it, `DigestEpisode` threads it to both LLM steps
- Stored on the episode record, not transient job args

**Post-extraction entity filter (new):**
- Regex filters for UUIDs, session IDs, module paths, file paths, key-value pairs, signal prefixes
- `@generic_names` MapSet blocking generic words

**Entity resolution containment match (new):**
- Word-boundary matching with 8-char minimum
- Catches: "ICHOR IV control plane" -> "ICHOR IV"

**Document chunking overhaul:**
- Parameters raised: target=1500, min=800, max=2500, overlap=150
- Section merging added
- Result: 57 chunks -> 4 chunks for 15KB doc; entity count 113 -> 23

**Chunking strategy modules:**
- `document_chunker/text.ex`, `json.ex`, `message.ex`, `sentence.ex`, `fixed.ex`, `hybrid.ex`, `density.ex`

---

## Existing Codebase Patterns for ADR-026

### `use` Macros

One custom `__using__` macro exists: `IchorWeb` (standard Phoenix dispatch pattern). No `use Ichor.*` macros in the application layer. This would be the first.

### DynamicSupervisor Usage

**Pattern A: Named module-based** -- `FleetSupervisor`, `TeamSupervisor`
**Pattern B: Inline anonymous** -- `Ichor.Factory.PlanRunSupervisor`, `Ichor.Factory.DynRunSupervisor`

### Registry

Single global `Ichor.Registry` with `keys: :unique`. All keys are tagged 2-tuples: `{:agent, id}`, `{:team, name}`, `{:run, run_id}`, `{:planning_run, run_id}`, `{:pipeline_run, run_id}`. Via-tuple pattern: `{:via, Registry, {Ichor.Registry, key, %{}}}`.

### Supervision Tree

22 children in `application.ex`, including `Ichor.RuntimeSupervisor` sub-supervisor with 11 runtime services. Signal subscribers are started at the top level.

### GenServer Conventions

- Named singletons: `name: __MODULE__`
- Dynamic: via-tuples with private `via/1` helper
- Async I/O: `Task.Supervisor.start_child(Ichor.TaskSupervisor, fn -> ... end)`
- Signal subscription in `init/1`
- Subscriber pattern: match specific signal names, catch-all for `%Message{}` and `_msg`

### Ash Embedded Resources

One example: `DecisionLog` with `data_layer: :embedded`. No domain registration. No primary key. `%DecisionLog{}` not patternable inside the resource module due to `@before_compile` -- requires companion `Helpers` module.

### Compile-Time Discovery

No existing patterns. Options: module attribute accumulation via `@before_compile`, Application env, or runtime `function_exported?` scan.

### Signal Data Shapes

All flat atom-keyed maps. `DecisionLog` wrapped as `%{log: %DecisionLog{}}`. `MemoriesBridge` has 40+ `narrate/2` clauses pattern-matching these maps.

---

## Dissolution Map: Modules Replaced by Signal-as-Projector

### Clean dissolutions (stateless, pure reaction → handler)

| Module | File | Subscribes | What it does | Becomes |
|---|---|---|---|---|
| **SessionLifecycle** | infrastructure/subscribers/session_lifecycle.ex | `:fleet` | Spawn/terminate agents and teams | 4 handlers |
| **SessionCleanupDispatcher** | infrastructure/subscribers/session_cleanup_dispatcher.ex | `:cleanup` | Insert Oban jobs | 2 handlers |
| **RunCleanupDispatcher** | factory/subscribers/run_cleanup_dispatcher.ex | `:cleanup` | Insert Oban jobs | 2 handlers |
| **ResearchIngestor** | factory/research_ingestor.ex | `:mes` | Read file, call Memories API | 1 handler |
| **ProjectIngestor** | factory/project_ingestor.ex | `:messages` | Parse message, create Ash resource | 1 handler |

### Accumulator dissolutions (stateful → Signal projector + handler)

| Module | File | State | Becomes |
|---|---|---|---|
| **MemoriesBridge** | memories_bridge.ex | Buffer per category, 30s timer, 40+ narrate clauses | 4 Memories Signal projectors + format/1 on structs |
| **EntropyTracker** | signals/entropy_tracker.ex | ETS sliding window per session | Signal projector (keeps ETS window) |
| **ProtocolTracker** | signals/protocol_tracker.ex | ETS trace table, heartbeat-driven stats | Signal projector (keeps ETS traces) |
| **SignalManager** | archon/signal_manager.ex | Rolling counts, attention queue | Signal projector (dashboard aggregation) |
| **TeamWatchdog** | archon/team_watchdog.ex | completed_runs MapSet | Signal projector + Oban handlers (collapses 3-hop chain) |
| **Buffer** | signals/buffer.ex | ETS ring buffer, seq counter | Signal projector (or dissolves if runtime broadcasts directly) |

### Complex dissolutions (timer-driven, multi-concern)

| Module | File | Why it's hard | Becomes |
|---|---|---|---|
| **AgentWatchdog** | signals/agent_watchdog.ex | Drives heartbeat timer, crash detection, escalation state machine, pane scanning -- 4 distinct concerns in one process | Splits into: heartbeat emitter, crash-detection Signal, escalation Signal, pane-scanner Signal |
| **EventBridge** | mesh/event_bridge.ex | Event→DecisionLog transform, DAG insertion, dynamic per-session subscriptions, hourly sweep | Signal projector with dynamic subscription support + Mesh handler |

### NOT dissolved (lifecycle processes that happen to subscribe)

| Module | File | Why it stays |
|---|---|---|
| **Factory.Runner** | factory/runner.ex | Per-run lifecycle GenServer. Subscribes narrowly for completion detection. Not a subscriber pattern. |
| **AgentProcess** | infrastructure/agent_process.ex | Per-agent lifecycle GenServer. Subscribes to own scoped events. Not a subscriber pattern. |
| **DashboardLive** | ichor_web/live/dashboard_live.ex | LiveView. Consumes signals for UI. Stays but gets cheaper inputs from Signal projectors. |

### Key architectural simplification

The current 3-hop chain **TeamWatchdog → emits cleanup signal → CleanupDispatchers → insert Oban job** collapses. TeamWatchdog's handler calls `Oban.insert` directly. Two dispatcher modules disappear entirely.

### Dissolution complexity summary

| Complexity | Count | Modules |
|---|---|---|
| Low (stateless, pure handler) | 5 | SessionLifecycle, SessionCleanupDispatcher, RunCleanupDispatcher, ResearchIngestor, ProjectIngestor |
| Medium (stateful accumulator) | 6 | MemoriesBridge, EntropyTracker, ProtocolTracker, SignalManager, TeamWatchdog, Buffer |
| High (multi-concern, timer-driven) | 2 | AgentWatchdog, EventBridge |
| Not dissolved | 3 | Factory.Runner, AgentProcess, DashboardLive |

---

## Emission Points: 61 Call Sites

### Direct call sites (37 explicit `Signals.emit` calls)

| # | File | Signal name | Data map | Natural key | Arity |
|---|------|-------------|----------|----|-------|
| 1 | dashboard_mes_handlers.ex:72 | `:mes_pipeline_generated` | `%{project_id}` | project_id | emit/2 |
| 2 | dashboard_mes_handlers.ex:87 | `:mes_pipeline_launched` | `%{project_id, session}` | project_id | emit/2 |
| 3 | dashboard_mes_handlers.ex:103 | `:mes_project_picked_up` | `%{project_id, session_id: "manual"}` | project_id | emit/2 |
| 4 | dashboard_session_control_handlers.ex:93 | `:hitl_operator_approved` | `%{session_id}` | session_id | emit/2 |
| 5 | dashboard_session_control_handlers.ex:106 | `:hitl_operator_rejected` | `%{session_id}` | session_id | emit/2 |
| 6 | dashboard_session_control_handlers.ex:155 | `:agent_stopped` | `%{session_id, reason: "dashboard_shutdown"}` | session_id | emit/2 |
| 7 | dashboard_session_control_handlers.ex:203 | `:agent_instructions` | `%{agent_class, instructions}` | agent_class | emit/3 |
| 8 | dashboard_session_control_handlers.ex:221 | `:mesh_pause` | `%{initiated_by: "god_mode"}` | nil | emit/2 |
| 9 | gateway_controller.ex:26 | `:decision_log` | `%{log: log}` | session_id | emit/2 |
| 10 | mesh/event_bridge.ex:42 | `:decision_log` | `%{log: log}` | session_id | emit/2 |
| 11 | mesh/event_bridge.ex:54 | `:topology_snapshot` | `%{nodes, edges}` | nil | emit/2 |
| 12 | mesh/causal_dag.ex:419 | `:dag_delta` | `%{session_id, added_nodes}` | session_id | emit/3 |
| 13 | workshop/spawn.ex:59 | `:team_spawn_requested` | `%{team_name, spec, source}` | request_id | emit/3 |
| 14 | workshop/team_spawn_handler.ex:37 | `:team_spawn_ready` | `%{session, team_name, agent_count, source}` | request_id | emit/3 |
| 15 | workshop/team_spawn_handler.ex:45 | `:team_spawn_failed` | `%{team_name, reason, source}` | request_id | emit/3 |
| 16 | workshop/team_spawn_handler.ex:58 | `:team_spawn_started` | `%{team_name, agent_count, source}` | request_id | emit/3 |
| 17 | archon/team_watchdog.ex:130 | `:run_cleanup_needed` | `%{run_id, action: :archive}` | run_id | emit/2 |
| 18 | archon/team_watchdog.ex:134 | `:run_cleanup_needed` | `%{run_id, action: :reset_tasks}` | run_id | emit/2 |
| 19 | archon/team_watchdog.ex:138 | `:session_cleanup_needed` | `%{session, action: :disband}` | session | emit/2 |
| 20 | archon/team_watchdog.ex:142 | `:session_cleanup_needed` | `%{session, action: :kill}` | session | emit/2 |
| 21 | memory_store.ex:287 | `:memory_changed` | `%{agent_name, event: :created}` | agent_name | emit/3 |
| 22 | memory_store.ex:467 | `:memory_changed` | `%{agent_name, event: :archival_insert}` | agent_name | emit/3 |
| 23 | signals/agent_watchdog.ex:68 | `:heartbeat` | `%{count: next}` | nil | emit/2 |
| 24 | signals/agent_watchdog.ex:146 | `:agent_crashed` | `%{session_id, team_name: nil}` | session_id | emit/2 |
| 25 | signals/agent_watchdog.ex:152 | `:agent_crashed` | `%{session_id, team_name}` | session_id | emit/2 |
| 26 | signals/agent_watchdog.ex:244 | `:nudge_warning` | `%{session_id, agent_name, level: 0}` | session_id | emit/2 |
| 27 | signals/agent_watchdog.ex:272 | `:nudge_sent` | `%{session_id, agent_name, level: 1}` | session_id | emit/2 |
| 28 | signals/agent_watchdog.ex:279 | `:nudge_escalated` | `%{session_id, agent_name, level: 2}` | session_id | emit/2 |
| 29 | signals/agent_watchdog.ex:289 | `:nudge_zombie` | `%{session_id, agent_name, level: 3}` | session_id | emit/2 |
| 30 | signals/agent_watchdog.ex:409 | dynamic (`:agent_done` or `:agent_blocked`) | `%{session_id, summary/reason}` | session_id | emit/2 |
| 31 | signals/entropy_tracker.ex:155 | `:entropy_alert` | `%{session_id, entropy_score}` | session_id | emit/2 |
| 32 | signals/entropy_tracker.ex:156 | `:node_state_update` | `%{agent_id, state: "alert_entropy"}` | agent_id | emit/2 |
| 33 | signals/entropy_tracker.ex:160 | `:node_state_update` | `%{agent_id, state: "blocked"}` | agent_id | emit/2 |
| 34 | signals/entropy_tracker.ex:165 | `:node_state_update` | `%{agent_id, state: "active"}` | agent_id | emit/2 |
| 35 | signals/event_stream/agent_lifecycle.ex:68 | dynamic (`:team_create_requested` or `:team_delete_requested`) | `%{team_name}` | team_name | emit/2 |
| 36 | signals/event_stream/agent_lifecycle.ex:94 | `:session_started` | `%{session_id, tmux_session, cwd, model, os_pid}` | session_id | emit/2 |
| 37 | signals/protocol_tracker.ex:59 | `:protocol_update` | `%{stats_map}` | nil | emit/2 |

### FromAsh notifier (24 action-to-signal mappings)

| # | Resource | Action | Signal name | Data shape | Natural key |
|---|----------|--------|-------------|------------|-------------|
| 38 | Pipeline | :create | `:pipeline_created` | `%{run_id, label, source}` | run_id |
| 39 | Pipeline | :complete | `:pipeline_completed` | `%{run_id, label, source}` | run_id |
| 40 | Pipeline | :fail | `:pipeline_completed` | same (consumers check status) | run_id |
| 41 | Pipeline | :archive | `:pipeline_archived` | `%{run_id, label, reason}` | run_id |
| 42 | PipelineTask | :claim | `:pipeline_task_claimed` | `%{task_id, run_id, external_id, subject, status, owner}` | run_id |
| 43 | PipelineTask | :complete | `:pipeline_task_completed` | same shape | run_id |
| 44 | PipelineTask | :fail | `:pipeline_task_failed` | same shape | run_id |
| 45 | PipelineTask | :reset | `:pipeline_task_reset` | same shape | run_id |
| 46 | Project | :create | `:project_created` | `%{id, project_id, title, type: :create}` | project_id |
| 47 | Project | :advance | `:project_advanced` | `%{id, project_id, title, type: :advance}` | project_id |
| 48 | Project | :add_artifact | `:project_artifact_created` | `%{project_id}` | project_id |
| 49 | Project | :add_roadmap_item | `:project_roadmap_item_created` | `%{project_id}` | project_id |
| 50 | Project | :pick_up | `:mes_project_picked_up` | `%{project_id, title, plugin, session_id}` | project_id |
| 51 | Project | :mark_compiled | `:mes_project_compiled` | same shape | project_id |
| 52 | Project | :mark_loaded | `:mes_plugin_loaded` | same shape | project_id |
| 53 | Project | :mark_failed | `:mes_project_failed` | same shape | project_id |
| 54 | WebhookDelivery | :enqueue | `:webhook_delivery_enqueued` | `%{delivery_id, agent_id, target_url, status, attempt_count}` | delivery_id |
| 55 | WebhookDelivery | :mark_delivered | `:webhook_delivery_delivered` | same shape | delivery_id |
| 56 | WebhookDelivery | :mark_dead | `:dead_letter` | same shape | delivery_id |
| 57 | HITLInterventionEvent | :record | `:hitl_intervention_recorded` | `%{event_id, session_id, agent_id, operator_id, action, details}` | session_id |
| 58 | CronJob | :schedule_once | `:cron_job_scheduled` | `%{job_id, agent_id, next_fire_at}` | agent_id |
| 59 | CronJob | :reschedule | `:cron_job_rescheduled` | same shape | agent_id |
| 60 | SettingsProject | :create | `:settings_project_created` | `%{project_id, name, is_active}` | project_id |
| 61 | SettingsProject | :update | `:settings_project_updated` | same shape | project_id |
| -- | SettingsProject | :destroy | `:settings_project_destroyed` | same shape | project_id |

### Four emission pathways

1. **FromAsh notifier (post-commit)** -- 7 resources, 24 mappings. Data from committed Ash record.
2. **Named wrapper modules** -- `AgentLifecycle` (4 lifecycle signals), `EventStream.AgentLifecycle` (hook-originated fleet signals).
3. **Direct `Signals.emit` calls** -- 37 sites across 16 modules. Fire-and-forget, inline with business logic.
4. **`Signals.Event` Ash actions** -- Programmatic emission surface for Archon/MCP tools.

### Partition key summary

| Key | Signal count | Examples |
|---|---|---|
| `session_id` | 16 | agent lifecycle, HITL, nudge, entropy |
| `run_id` | 8 | pipeline, MES run |
| `project_id` | 13 | project, MES project, settings |
| `agent_id` | 6 | webhook, cron, node state |
| `team_name` | 4 | team lifecycle |
| `request_id` | 4 | team spawn (ephemeral) |
| `nil` (broadcast) | ~8 | heartbeat, topology, stats |

---

## Topic Taxonomy: Domain Fact Naming

### Conventions
- Format: `domain.entity.verb_past_tense`
- They describe what happened, not framework internals
- If you need to know Elixir/Ash/Phoenix to understand the name, it's wrong

### Domain: `agent`

| Current atom | Proposed topic | Natural key |
|---|---|---|
| `agent_started` | `agent.process.started` | session_id |
| `agent_paused` | `agent.process.paused` | session_id |
| `agent_resumed` | `agent.process.resumed` | session_id |
| `agent_stopped` | `agent.process.stopped` | session_id |
| `agent_evicted` | `agent.process.evicted` | session_id |
| `agent_reaped` | `agent.process.reaped` | session_id |
| `agent_discovered` | `agent.process.discovered` | session_id |
| `agent_crashed` | `agent.process.crashed` | session_id |
| `agent_spawned` | `agent.process.spawned` | session_id |
| `session_started` | `agent.session.started` | session_id |
| `session_ended` | `agent.session.ended` | session_id |
| `agent_tmux_gone` | `agent.tmux.gone` | agent_id |
| `terminal_output` | `agent.terminal.output_received` | session_id |
| `agent_event` | `agent.event.received` | session_id |
| `agent_message_intercepted` | `agent.message.intercepted` | session_id |
| `mailbox_message` | `agent.mailbox.message_received` | session_id |
| `agent_instructions` | `agent.instructions.pushed` | agent_class |
| `scheduled_job` | `agent.job.fired` | agent_id |
| `agent_done` | `agent.work.completed` | session_id |
| `agent_blocked` | `agent.work.blocked` | session_id |

### Domain: `fleet`

| Current atom | Proposed topic | Natural key |
|---|---|---|
| `team_created` | `fleet.team.created` | name |
| `team_disbanded` | `fleet.team.disbanded` | team_name |
| `team_create_requested` | `fleet.team.create_requested` | team_name |
| `team_delete_requested` | `fleet.team.delete_requested` | team_name |
| `team_spawn_requested` | `fleet.team.spawn_requested` | team_name |
| `team_spawn_started` | `fleet.team.spawn_started` | team_name |
| `team_spawn_ready` | `fleet.team.spawn_completed` | team_name |
| `team_spawn_failed` | `fleet.team.spawn_failed` | team_name |
| `hosts_changed` | `fleet.cluster.node_changed` | nil |
| `fleet_changed` | `fleet.registry.changed` | agent_id |
| `run_complete` | `fleet.run.completed` | run_id |
| `run_terminated` | `fleet.run.terminated` | run_id |

### Domain: `team`

| Current atom | Proposed topic | Natural key |
|---|---|---|
| `task_created` | `team.task.created` | task.id |
| `task_updated` | `team.task.updated` | task.id |
| `task_deleted` | `team.task.deleted` | task_id |
| `tasks_updated` | `team.tasklist.refreshed` | team_name |

### Domain: `monitoring`

| Current atom | Proposed topic | Natural key |
|---|---|---|
| `protocol_update` | `monitoring.protocol.stats_recomputed` | nil |
| `gate_passed` | `monitoring.gate.passed` | session_id |
| `gate_failed` | `monitoring.gate.failed` | session_id |
| `watchdog_sweep` | `monitoring.watchdog.swept` | nil |

### Domain: `nudge`

| Current atom | Proposed topic | Natural key |
|---|---|---|
| `nudge_warning` | `nudge.escalation.warned` | session_id |
| `nudge_sent` | `nudge.escalation.nudged` | session_id |
| `nudge_escalated` | `nudge.escalation.hitl_paused` | session_id |
| `nudge_zombie` | `nudge.escalation.zombied` | session_id |

### Domain: `gateway`

| Current atom | Proposed topic | Natural key |
|---|---|---|
| `decision_log` | `gateway.message.routed` | envelope_id |
| `schema_violation` | `gateway.schema.violated` | nil |
| `node_state_update` | `gateway.topology.node_updated` | agent_id |
| `entropy_alert` | `gateway.entropy.detected` | session_id |
| `topology_snapshot` | `gateway.topology.snapshot_taken` | nil |
| `capability_update` | `gateway.capability.updated` | nil |
| `dead_letter` | `gateway.webhook.dead_lettered` | delivery_id |
| `webhook_delivery_enqueued` | `gateway.webhook.enqueued` | delivery_id |
| `webhook_delivery_delivered` | `gateway.webhook.delivered` | delivery_id |
| `gateway_audit` | `gateway.routing.audited` | envelope_id |
| `mesh_pause` | `gateway.mesh.paused` | nil |
| `cron_job_scheduled` | `gateway.cron.scheduled` | job_id |
| `cron_job_rescheduled` | `gateway.cron.rescheduled` | job_id |

### Domain: `hitl`

| Current atom | Proposed topic | Natural key |
|---|---|---|
| `gate_open` | `hitl.gate.opened` | session_id |
| `gate_close` | `hitl.gate.closed` | session_id |
| `hitl_auto_released` | `hitl.gate.auto_released` | session_id |
| `hitl_operator_approved` | `hitl.operator.approved` | session_id |
| `hitl_operator_rejected` | `hitl.operator.rejected` | session_id |
| `hitl_intervention_recorded` | `hitl.operator.intervention_recorded` | event_id |

### Domain: `mesh`

| Current atom | Proposed topic | Natural key |
|---|---|---|
| `dag_delta` | `mesh.dag.updated` | session_id |

### Domain: `memory`

| Current atom | Proposed topic | Natural key |
|---|---|---|
| `block_changed` | `memory.block.modified` | block_id |
| `memory_changed` | `memory.agent.changed` | agent_name |

### Domain: `message`

| Current atom | Proposed topic | Natural key |
|---|---|---|
| `message_delivered` | `message.agent.delivered` | agent_id |

### Domain: `mes`

| Current atom | Proposed topic | Natural key |
|---|---|---|
| `mes_scheduler_paused` | `mes.scheduler.paused` | tick |
| `mes_scheduler_resumed` | `mes.scheduler.resumed` | tick |
| `mes_cycle_started` | `mes.cycle.started` | run_id |
| `mes_cycle_skipped` | `mes.cycle.skipped` | tick |
| `mes_cycle_failed` | `mes.cycle.failed` | run_id |
| `mes_cycle_timeout` | `mes.cycle.timed_out` | run_id |
| `mes_run_started` | `mes.run.started` | run_id |
| `mes_run_terminated` | `mes.run.terminated` | run_id |
| `mes_maintenance_cleaned` | `mes.maintenance.cleaned` | run_id |
| `mes_maintenance_error` | `mes.maintenance.failed` | run_id |
| `mes_maintenance_skipped` | `mes.maintenance.skipped` | run_id |
| `mes_tmux_session_created` | `mes.tmux.session_created` | session |
| `mes_tmux_spawn_failed` | `mes.tmux.spawn_failed` | session |
| `mes_team_ready` | `mes.team.ready` | session |
| `mes_team_killed` | `mes.team.killed` | session |
| `mes_team_spawn_failed` | `mes.team.spawn_failed` | session |
| `mes_agent_registered` | `mes.agent.registered` | agent_name |
| `mes_agent_register_failed` | `mes.agent.registration_failed` | agent_name |
| `mes_agent_stopped` | `mes.agent.stopped` | agent_id |
| `mes_operator_ensured` | `mes.operator.ensured` | nil |
| `mes_project_created` | `mes.project.created` | project_id |
| `mes_project_picked_up` | `mes.project.claimed` | project_id |
| `mes_project_compiled` | `mes.project.compiled` | project_id |
| `mes_project_failed` | `mes.project.failed` | project_id |
| `mes_prompts_written` | `mes.prompts.written` | run_id |
| `mes_cleanup` | `mes.session.cleaned` | target |
| `mes_plugin_loaded` | `mes.plugin.loaded` | project_id |
| `mes_plugin_compile_failed` | `mes.plugin.compile_failed` | project_id |
| `mes_quality_gate_passed` | `mes.gate.passed` | run_id |
| `mes_quality_gate_failed` | `mes.gate.failed` | run_id |
| `mes_quality_gate_escalated` | `mes.gate.escalated` | run_id |
| `mes_research_ingested` | `mes.research.ingested` | run_id |
| `mes_research_ingest_failed` | `mes.research.ingest_failed` | run_id |
| `mes_output_unhandled` | `mes.output.unhandled` | run_id |
| `mes_pipeline_generated` | `mes.pipeline.generated` | project_id |
| `mes_pipeline_launched` | `mes.pipeline.launched` | project_id |
| `mes_corrective_agent_spawned` | `mes.corrective_agent.spawned` | run_id |
| `mes_corrective_agent_failed` | `mes.corrective_agent.spawn_failed` | run_id |

### Domain: `planning`

| Current atom | Proposed topic | Natural key |
|---|---|---|
| `planning_team_ready` | `planning.team.ready` | session |
| `planning_team_spawn_failed` | `planning.team.spawn_failed` | session |
| `planning_team_killed` | `planning.team.killed` | session |
| `planning_tmux_gone` | `planning.tmux.gone` | session |
| `planning_run_complete` | `planning.run.completed` | run_id |
| `planning_run_terminated` | `planning.run.terminated` | run_id |
| `project_created` | `planning.project.created` | project_id |
| `project_advanced` | `planning.project.advanced` | project_id |
| `project_artifact_created` | `planning.project.artifact_created` | project_id |
| `project_roadmap_item_created` | `planning.project.roadmap_item_created` | project_id |

### Domain: `pipeline`

| Current atom | Proposed topic | Natural key |
|---|---|---|
| `pipeline_created` | `pipeline.run.created` | run_id |
| `pipeline_ready` | `pipeline.run.started` | run_id |
| `pipeline_completed` | `pipeline.run.completed` | run_id |
| `pipeline_archived` | `pipeline.run.archived` | run_id |
| `pipeline_reconciled` | `pipeline.run.reconciled` | pipeline_id |
| `pipeline_task_claimed` | `pipeline.task.claimed` | task_id |
| `pipeline_task_completed` | `pipeline.task.completed` | task_id |
| `pipeline_task_failed` | `pipeline.task.failed` | task_id |
| `pipeline_task_reset` | `pipeline.task.reset` | task_id |
| `pipeline_tmux_gone` | `pipeline.tmux.gone` | session |
| `pipeline_health_report` | `pipeline.health.reported` | run_id |
| `pipeline_status` | `pipeline.status.snapshot_taken` | nil |

### Domain: `cleanup`

| Current atom | Proposed topic | Natural key |
|---|---|---|
| `run_cleanup_needed` | `cleanup.run.needed` | run_id |
| `session_cleanup_needed` | `cleanup.session.needed` | session |

### Domain: `settings`

| Current atom | Proposed topic | Natural key |
|---|---|---|
| `settings_project_created` | `settings.project.created` | project_id |
| `settings_project_updated` | `settings.project.updated` | project_id |
| `settings_project_destroyed` | `settings.project.deleted` | project_id |

### Domain: `system`

| Current atom | Proposed topic | Natural key |
|---|---|---|
| `dashboard_command` | `system.dashboard.command_received` | command |

---

## Infrastructure Noise: Recommended for Removal

| Signal | Why | Alternative |
|---|---|---|
| `heartbeat` | System health metric, not domain fact | Telemetry counter |
| `registry_changed` | ETS mutation, no payload | Subscribe to `agent.session.*` |
| `new_event` | Meaningless name, ingestion receipt | Replaced by GenStage event envelope |
| `mes_scheduler_init` | GenServer startup notification | Structured log |
| `mes_run_init` | GenServer.init callback noise | Structured log |
| `planning_run_init` | GenServer.init callback noise | Structured log |
| `mes_maintenance_init` | GenServer startup notification | Structured log |
| `mes_tmux_spawning` | "About to" event, not a fact | `mes.tmux.session_created` is the fact |
| `mes_tmux_window_created` | Incremental provisioning step | `mes.team.ready` is what matters |
| `mes_tick` | Internal scheduler tick | Telemetry counter |
| `watchdog_sweep` | Internal process diagnostic | Structured log |

---

## Consolidation Candidates

| Group | Signals | Recommendation |
|---|---|---|
| Tmux gone | `agent_tmux_gone`, `planning_tmux_gone`, `pipeline_tmux_gone` | Consider single `run.tmux.gone` with `run_kind` field |
| Gate pass/fail | `gate_passed/failed` vs `mes_quality_gate_passed/failed` | Keep both (different scope: session vs run) |
| Agent online | `mes_agent_registered` vs `agent_started` | May be redundant, investigate |
| HITL / pause | `agent_paused/resumed` vs `gate_open/close` | Link via `causation_id` |
| Run complete | `run_complete/terminated` (fleet) vs domain-specific | Keep both layers (fleet = cross-kind aggregate) |
| Project created | `mes_project_created` vs `project_created` | Different facts: brief submitted vs Ash record created |

---

## Integration Strategy

The single hook point is `Ichor.Signals.Runtime.emit/2` and `emit/3`. Every signal in the system flows through these two functions. Dual-emit here (bridge `%Message{}` into `%Event{}` and push to `Ichor.Events.Ingress`) means all 143 signals automatically feed both pipelines with zero changes to the 61 call sites.
