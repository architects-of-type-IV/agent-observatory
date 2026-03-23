# Supervision Tree Trace

Full trace of `Ichor.Application` -- every child, dependency, ETS table, signal flow.

## Top-Level Tree (application.ex, :one_for_one)

### Pre-supervision init (runs before children start)

| Call | Primitive | Owner | Risk |
|------|-----------|-------|------|
| `AgentLaunch.init_counter()` | `:persistent_term` + `:atomics` | Global | Wrong primitive (GC-hostile for a counter) |
| `Bus.start_message_log()` | ETS `:public :ordered_set` | Application process | TOCTOU race on cap. Needs GenServer per SF-7. |
| `Notes.init()` | ETS `:public :set` | Application process | Domainless module. O(n) eviction. UI-only. |

### Post-startup (unsupervised Task)

| Call | Risk |
|------|------|
| `ensure_tmux_server()` | Shares Task with recover_jobs. Can block on tmux. |
| `CronScheduler.recover_jobs()` | Swallows all failures silently. Lost job recovery undetectable. |

### Children (22 entries)

| # | Child | Domain | Type | Signals Sub | Signals Emit | ETS Owned |
|---|-------|--------|------|-------------|-------------|-----------|
| 1 | IchorWeb.Telemetry | Web | Supervisor | - | - | - |
| 2 | Ichor.Repo | Infra | GenServer | - | - | - |
| 3 | Oban | Infra | Supervisor | - | - | - |
| 4 | Ecto.Migrator | Infra | Task | - | - | - |
| 5 | DNSCluster | Infra | GenServer | - | - | - |
| 6 | Phoenix.PubSub | Signals | Supervisor | - | - | - |
| 7 | Registry | Infra | Registry | - | - | - |
| 8 | :pg scope | Infra | Process group | - | - | - |
| 9 | HostRegistry | Infra | GenServer | - | :hosts_changed | - |
| 10 | **RuntimeSupervisor** | Mixed | Supervisor | (see below) | (see below) | (see below) |
| 11 | FleetSupervisor | Infra | DynamicSupervisor | - | :team_disbanded | - |
| 12 | SessionLifecycle | Infra | GenServer | :fleet | - | - |
| 13 | RunCleanupDispatcher | Factory | GenServer | :cleanup | - | - |
| 14 | SessionCleanupDispatcher | Infra | GenServer | :cleanup | - | - |
| 15 | Mesh.Supervisor | Mesh | Supervisor | (see below) | (see below) | (see below) |
| 16 | TaskSupervisor | Infra | Task.Supervisor | - | - | - |
| 17 | Factory.LifecycleSupervisor | Factory | Supervisor | (see below) | (see below) | - |
| 18 | TeamSpawnHandler | Workshop | GenServer | :fleet | :team_spawn_* | - |
| 19 | PlanRunSupervisor | Factory | DynamicSupervisor | - | - | - |
| 20 | DynRunSupervisor | Factory | DynamicSupervisor | - | - | - |
| 21 | MemoriesBridge | Infra | GenServer | ALL categories | - | - |
| 22 | IchorWeb.Endpoint | Web | Supervisor | - | - | - |

## RuntimeSupervisor (child 10, :one_for_one)

11 children mixing 4 domains under one supervisor:

| # | Child | Domain | Signals Sub | Signals Emit | ETS |
|---|-------|--------|-------------|-------------|-----|
| 1 | MemoryStore | Archon | - | :memory_changed | 4 tables (:public) |
| 2 | EventStream | Signals | :fleet | :new_event, :agent_event, :session_ended, :agent_message_intercepted, :agent_evicted | 4 tables (:protected) |
| 3 | TmuxDiscovery | Infra | - | :fleet_changed, :agent_reaped, :agent_discovered | - |
| 4 | EntropyTracker | Signals | :events | :entropy_alert, :node_state_update | 1 table (:private) |
| 5 | HITLRelay | Infra | - | :gate_open, :gate_close, :auto_released, :decision_log | 1 table (Buffer) |
| 6 | OutputCapture | Infra | - | :terminal_output | - |
| 7 | AgentWatchdog | Signals | :events, :fleet | :heartbeat, :agent_crashed, :nudge_*, :agent_done, :agent_blocked | - |
| 8 | ProtocolTracker | Signals | :events, :heartbeat | :protocol_update | 1 table (:public) |
| 9 | Buffer | Signals | ALL categories | (rebroadcast on signals:feed) | 1 table (:public) |
| 10 | SignalManager | Archon | ALL categories | - | - |
| 11 | TeamWatchdog | Archon | :fleet, :pipeline(unused), :planning(unused), :monitoring(unused) | :run_cleanup_needed, :session_cleanup_needed | - |

### Domain breakdown of RuntimeSupervisor children
- **Signals (5):** EventStream, EntropyTracker, AgentWatchdog, ProtocolTracker, Buffer
- **Archon (3):** MemoryStore, SignalManager, TeamWatchdog
- **Infrastructure (3):** TmuxDiscovery, HITLRelay, OutputCapture

## Mesh.Supervisor (child 15, :rest_for_one)

| # | Child | Signals Sub | Signals Emit | ETS |
|---|-------|-------------|-------------|-----|
| 1 | CausalDAG | - | :dag_delta | 2 named + dynamic per-session (:public) |
| 2 | EventBridge | :events, :dag_delta(scoped) | :decision_log, :topology_snapshot | - |

`:rest_for_one` is correct: CausalDAG must restart before EventBridge (EventBridge holds subscription state for DAG sessions).

## Factory.LifecycleSupervisor (child 17, :rest_for_one)

| # | Child | Signals Sub | Signals Emit |
|---|-------|-------------|-------------|
| 0 | BuildRunSupervisor | - | - |
| 1 | ProjectIngestor | :messages | :mes_project_created |
| 2 | ResearchIngestor | :mes | :mes_research_ingested/failed |
| 3 | CompletionHandler | :pipeline | :mes_plugin_compile_failed, :mes_output_unhandled |

Init side effect: `ensure_operator_process/0` spawns the operator AgentProcess. Swallows spawn failures silently.

## Subscribers (children 12-14, stateless dispatchers)

All three are stateless (`%{}` state), re-subscribe correctly on restart, Oban unique jobs provide idempotency.

| Subscriber | Subscribes to | Handles | Side effect |
|------------|--------------|---------|-------------|
| SessionLifecycle | :fleet | session_started/ended, team_create/delete_requested | FleetSupervisor spawn/terminate |
| RunCleanupDispatcher | :cleanup | run_cleanup_needed | Oban insert (unique 60s) |
| SessionCleanupDispatcher | :cleanup | session_cleanup_needed | Oban insert (unique 60s) |

## Key Runtime Dependencies

```
EventStream --(:new_event)--> EntropyTracker, AgentWatchdog, ProtocolTracker, EventBridge
AgentWatchdog --(:heartbeat)--> ProtocolTracker
AgentWatchdog --(call)--> HITLRelay.pause/4 (synchronous, can timeout)
AgentWatchdog --(call)--> Bus.send/1 (nudge messages)
AgentWatchdog --(call)--> Factory.Board (task reassignment -- cross-domain)
TeamWatchdog --(:run_cleanup_needed)--> RunCleanupDispatcher
TeamWatchdog --(:session_cleanup_needed)--> SessionCleanupDispatcher
ProjectIngestor --(:mes_project_created)--> ResearchIngestor
EventBridge --(call)--> CausalDAG.insert/2 (synchronous)
```

## Issues Found

1. **RuntimeSupervisor mixes 4 domains** under :one_for_one -- Signals, Archon, Infrastructure children have no ordering guarantees
2. **Bus.start_message_log** TOCTOU race -- concurrent writers can exceed cap
3. **Notes.init** domainless -- UI-only concern at top level
4. **CronScheduler.recover_jobs** in naked Task -- failures swallowed
5. **ensure_operator_process** swallows spawn failures -- ingestion pipeline silently dead
6. **AgentWatchdog calls HITLRelay.pause synchronously** in 5s tick -- can block beat
7. **AgentWatchdog calls Factory.Board directly** -- cross-domain write from Signals into Factory
8. **MemoryStore** at top-level `Ichor` namespace -- should be `Ichor.Archon` or `Ichor.Infrastructure`
9. **3 unused TeamWatchdog subscriptions** (:pipeline, :planning, :monitoring)
10. **CausalDAG ETS tables :public** -- inconsistent with SF-7 (:protected policy)
