# ICHOR IV Redesign Blueprint

## Design Principles

### Architect's Vision
- Ash is a declarative framework: config over code. 90% of our code can be declared.
- Focus on vertical slices and Ash Domain models.
- Fleet = Workshop. One boundary for agents, teams, blueprints, prompts, launching.
- Prompts belong to agents (fleet), not projects. Different run types select different blueprints.
- Signals contracts from ichor_contracts must move into the main app.
- The target is great simplified design, not just fewer files.

### Codex's Analysis
- The codebase is over-partitioned by semantic naming, not by stable runtime boundaries.
- Most modules are facades, projections, or orchestration slices around ~5 real centers.
- Ephemeral Ash resources (Agent, Team, Message, Error, Task, Session) should become plain query modules.
- Preparations are unnecessary indirection -- query modules can read from ETS/runtime directly.
- Delete or absorb: not fold. Redesign so modules aren't needed.

### Combined Rules
1. One folder per real runtime boundary
2. Ash resources for durable records ONLY (Project, Node, Artifact, RoadmapItem, Run, Job, Blueprint, WebhookDelivery, CronJob)
3. Plain query modules for ephemeral state (agents, teams, events, sessions)
4. Ash DSL declares behavior: actions, validations, changes, calculations, aggregates, notifiers
5. Prompts are agent configuration, not project orchestration
6. Transport adapters separated from event projections
7. Supervisors aligned with failure domains, not conceptual brands

---

## Current State (127 files)

```
lib/ichor/
├── application.ex
├── repo.ex
├── system_supervisor.ex
├── observation_supervisor.ex
├── agent_watchdog.ex
├── event_buffer.ex              # shim delegating to Events.Runtime
├── memories_bridge.ex
├── memory_store.ex
├── memory_store/
│   ├── persistence.ex
│   └── storage.ex
├── messages/
│   └── bus.ex
├── notes.ex
├── protocol_tracker.ex
├── quality_gate.ex
├── archon/
│   ├── chat.ex
│   ├── command_manifest.ex
│   ├── memories_client.ex
│   ├── signal_manager.ex
│   └── team_watchdog.ex
├── architecture/
│   └── boundary_audit.ex
├── control/
│   ├── control.ex                # Ash Domain (pure declaration)
│   ├── agent_process.ex
│   ├── agent_type.ex
│   ├── agent.ex                  # Ash Resource (Simple data layer, ephemeral)
│   ├── team.ex                   # Ash Resource (Simple data layer, ephemeral)
│   ├── blueprint_state.ex
│   ├── blueprint.ex              # Ash Resource (SQLite, durable)
│   ├── fleet_supervisor.ex
│   ├── host_registry.ex
│   ├── presets.ex
│   ├── team_spec_builder.ex
│   ├── team_supervisor.ex
│   ├── tmux_helpers.ex
│   ├── analysis/
│   │   ├── agent_health.ex
│   │   ├── queries.ex
│   │   └── session_eviction.ex
│   ├── lifecycle/
│   │   ├── agent_launch.ex
│   │   ├── agent_spec.ex
│   │   ├── cleanup.ex
│   │   ├── registration.ex
│   │   ├── team_launch.ex
│   │   ├── team_spec.ex
│   │   ├── tmux_launcher.ex
│   │   └── tmux_script.ex
│   ├── types/
│   │   └── health_status.ex
│   └── views/preparations/
│       ├── load_agents.ex
│       └── load_teams.ex
├── events/
│   ├── event.ex
│   └── runtime.ex
├── gateway/
│   ├── agent_registry/
│   │   └── agent_entry.ex
│   ├── channel.ex
│   ├── channels/
│   │   ├── ansi_utils.ex
│   │   ├── mailbox_adapter.ex
│   │   ├── ssh_tmux.ex
│   │   ├── tmux.ex
│   │   └── webhook_adapter.ex
│   ├── cron_job.ex
│   ├── cron_scheduler.ex
│   ├── entropy_tracker.ex
│   ├── event_bridge.ex
│   ├── hitl_intervention_event.ex
│   ├── hitl_relay.ex
│   ├── output_capture.ex
│   ├── schema_interceptor.ex
│   ├── tmux_discovery.ex
│   ├── webhook_delivery.ex
│   └── webhook_router.ex
├── mesh/
│   ├── causal_dag.ex
│   ├── decision_log.ex
│   └── decision_log/helpers.ex
├── observability/
│   ├── observability.ex          # Ash Domain (pure declaration)
│   ├── error.ex                  # Ash Resource (Simple, ephemeral)
│   ├── event.ex                  # Ash Resource (SQLite, durable)
│   ├── janitor.ex
│   ├── message.ex                # Ash Resource (Simple, ephemeral)
│   ├── session.ex                # Ash Resource (SQLite, durable)
│   ├── task.ex                   # Ash Resource (Simple, ephemeral)
│   └── preparations/
│       ├── event_buffer_reader.ex
│       ├── load_errors.ex
│       ├── load_messages.ex
│       └── load_tasks.ex
├── plugs/
│   └── operator_auth.ex
├── projects/
│   ├── projects.ex               # Ash Domain (pure declaration)
│   ├── artifact.ex               # Ash Resource (SQLite, durable)
│   ├── completion_handler.ex
│   ├── dag_generator.ex
│   ├── dag_prompts.ex            # WRONG: belongs in fleet
│   ├── date_utils.ex
│   ├── graph.ex
│   ├── janitor.ex
│   ├── job.ex                    # Ash Resource (SQLite, durable)
│   ├── lifecycle_supervisor.ex
│   ├── mode_prompts.ex           # WRONG: belongs in fleet
│   ├── node.ex                   # Ash Resource (SQLite, durable)
│   ├── pipeline_stage.ex
│   ├── project_ingestor.ex
│   ├── project.ex                # Ash Resource (SQLite, durable)
│   ├── research_context.ex
│   ├── research_ingestor.ex
│   ├── research_store.ex
│   ├── roadmap_item.ex           # Ash Resource (SQLite, durable)
│   ├── run.ex                    # Ash Resource (SQLite, durable)
│   ├── runner.ex
│   ├── runtime.ex
│   ├── scheduler.ex
│   ├── spawn.ex
│   ├── subsystem_loader.ex
│   ├── subsystem_scaffold.ex
│   ├── team_prompts.ex           # WRONG: belongs in fleet
│   ├── team_spec.ex
│   ├── types/
│   │   └── work_status.ex
│   ├── job/changes/
│   │   └── sync_run_process.ex
│   └── job/preparations/
│       └── filter_available.ex
├── signals/
│   ├── buffer.ex
│   ├── catalog.ex
│   ├── event.ex
│   ├── from_ash.ex
│   └── runtime.ex
├── tasks/
│   ├── board.ex
│   └── jsonl_store.ex
└── tools/
    ├── tools.ex                  # Ash Domain
    ├── agent_memory.ex
    ├── genesis.ex
    ├── profiles.ex
    ├── project_execution.ex
    ├── runtime_ops.ex
    └── archon/
        └── memory.ex

ALSO in subsystems/ichor_contracts/lib/ichor/:
├── signals.ex                    # facade
├── signals/behaviour.ex          # MOVE to main app
├── signals/message.ex            # MOVE to main app
├── signals/noop.ex               # MOVE to main app
├── signals/topics.ex             # MOVE to main app
├── pub_sub.ex                    # MOVE to main app
└── mes/subsystem.ex + info.ex    # MOVE to main app
```

---

## Target State (~55 files)

```
lib/ichor/
├── application.ex
├── repo.ex
│
├── events/                        # Vertical slice: everything event/signal
│   ├── domain.ex                  # Ash Domain
│   ├── runtime.ex                 # GenServer: ingestion, liveness, heartbeat, ETS
│   ├── event.ex                   # struct + Ash Resource (durable events in SQLite)
│   ├── signals.ex                 # emit/subscribe/broadcast (absorbs signals/runtime + contracts)
│   ├── catalog.ex                 # signal definitions
│   ├── from_ash.ex                # Ash notifier
│   ├── query.ex                   # replaces Message/Error/Task/Session Ash resources with plain reads
│   └── projections/
│       ├── attention.ex           # absorbs SignalManager
│       ├── decision_log.ex        # absorbs Mesh.DecisionLog + EventBridge DAG logic
│       ├── topology.ex            # absorbs CausalDAG + TopologyBuilder
│       └── traces.ex              # absorbs ProtocolTracker
│
├── fleet/                         # Vertical slice: agents + teams + workshop
│   ├── domain.ex                  # Ash Domain
│   ├── runtime.ex                 # GenServer: fleet + team supervision, discovery, watchdog
│   ├── agent_process.ex           # GenServer per agent
│   ├── launcher.ex                # absorbs agent_launch + team_launch + registration + cleanup
│   ├── query.ex                   # replaces Agent/Team Ash resources with plain reads
│   ├── blueprint.ex               # Ash Resource (SQLite, durable)
│   ├── presets.ex                 # Workshop preset definitions
│   ├── host_registry.ex           # ETS host tracking
│   └── prompts/                   # Agent prompt templates (ALL prompts live here)
│       ├── mes.ex                 # MES team prompts
│       ├── genesis.ex             # Genesis mode prompts
│       └── dag.ex                 # DAG pipeline prompts
│
├── projects/                      # Vertical slice: planning + execution
│   ├── domain.ex                  # Ash Domain
│   ├── runtime.ex                 # GenServer: DAG poller, task refresh, health, corrective actions
│   ├── run_manager.ex             # GenServer: unified runner (absorbs scheduler, janitor, completion)
│   ├── spawn.ex                   # spawn(:mes/:dag/:genesis) + team spec building
│   ├── graph.ex                   # DAG analysis
│   ├── ingest.ex                  # project brief + research ingestion
│   ├── build.ex                   # subsystem scaffold + loader
│   └── schemas/                   # Durable Ash Resources only
│       ├── project.ex
│       ├── node.ex
│       ├── artifact.ex
│       ├── roadmap_item.ex
│       ├── run.ex
│       └── job.ex
│
├── memory/                        # Vertical slice: agent memory
│   ├── store.ex                   # GenServer: ETS + flush
│   ├── storage.ex                 # ETS operations
│   ├── persistence.ex             # disk I/O
│   ├── bridge.ex                  # signal→Memories API batching
│   └── client.ex                  # HTTP client to external Memories service
│
├── transport/                     # IO boundaries only
│   ├── message_bus.ex             # single delivery authority
│   ├── tmux.ex                    # tmux adapter
│   ├── ssh_tmux.ex                # SSH tmux adapter
│   ├── mailbox.ex                 # BEAM mailbox adapter
│   ├── webhook.ex                 # webhook adapter + router + delivery resource
│   ├── cron.ex                    # cron scheduler + job resource
│   ├── hitl.ex                    # HITL relay + intervention resource
│   └── output_capture.ex          # terminal output polling
│
├── tools/                         # MCP/AshAi tool surface
│   ├── domain.ex                  # Ash Domain
│   ├── fleet.ex                   # fleet/agent/team tools
│   ├── projects.ex                # project/run/genesis tools
│   ├── memory.ex                  # core + archon memory tools
│   └── profiles.ex                # tool scoping per audience
│
├── tasks/                         # Task board
│   ├── board.ex
│   └── jsonl_store.ex
│
├── notes.ex
└── plugs/
    └── operator_auth.ex
```

---

## Key Design Decisions

### 1. Fleet = Workshop
The workshop page designs teams. The fleet runs them. One boundary owns both.
Agent prompts are agent configuration -- they belong in fleet/prompts/, not projects/.

### 2. Ash Resources: durable only
Keep Ash for persisted data: Project, Node, Artifact, RoadmapItem, Run, Job, Blueprint, Event, Session.
Delete ephemeral Ash resources (Agent, Team, Message, Error, Task) -- replace with `fleet/query.ex` and `events/query.ex` that read from ETS/runtime.

### 3. Config over code
90% of logic should be declared in Ash DSL: actions, validations, changes, calculations, aggregates, notifiers, code_interface.
GenServers only for: runtime state machines, supervision, timers, ETS ownership.
Everything else: Ash declarations or pure functions.

### 4. Signals contracts move in
`subsystems/ichor_contracts/lib/ichor/signals/` moves into `lib/ichor/events/signals.ex`.
No more external contract library for a single-app codebase.

### 5. Projections, not services
SignalManager, ProtocolTracker, EventBridge, CausalDAG, TopologyBuilder -- these are all event-derived projections. They live under `events/projections/`, not as standalone GenServers.

### 6. Transport = IO only
Message bus, tmux, webhook, cron, HITL, output capture. No business logic. No event projections. Just delivery.

---

## Migration Path

### Phase 1: Events vertical
- Create events/domain.ex, events/query.ex, events/signals.ex
- Move signals contracts from ichor_contracts
- Move projections (SignalManager→attention, EventBridge→decision_log, CausalDAG→topology, ProtocolTracker→traces)
- Delete ephemeral Observability Ash resources + preparations

### Phase 2: Fleet vertical
- Create fleet/domain.ex, fleet/runtime.ex, fleet/query.ex, fleet/launcher.ex
- Move prompts from projects/ to fleet/prompts/
- Absorb control/lifecycle/* into launcher
- Absorb AgentWatchdog + TmuxDiscovery into fleet/runtime
- Delete control/ directory

### Phase 3: Projects vertical
- Consolidate run_manager (absorb scheduler, janitor, completion_handler)
- Consolidate ingest (project_ingestor + research_ingestor)
- Consolidate build (subsystem_scaffold + subsystem_loader)
- Move schemas into projects/schemas/
- Delete lifecycle_supervisor

### Phase 4: Transport + Memory
- Move message bus, channel adapters, webhook, cron, hitl, output_capture into transport/
- Rename memory_store → memory
- Move MemoriesBridge + MemoriesClient into memory/
- Delete gateway/ directory

### Phase 5: Tools + cleanup
- Align tools to new boundaries (fleet, projects, memory)
- Delete architecture/, mesh/ (absorbed into events/projections)
- Update all docs
