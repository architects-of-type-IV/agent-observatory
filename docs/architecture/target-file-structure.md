# Target File Structure
Related: [Index](INDEX.md) | [Decisions](decisions.md) | [Supervision Tree](supervision-tree.md)

Target: ~45-60 modules. Current: 127. Source: codex target structure (2026-03-20) + blueprint refinements.

---

## Target `lib/ichor/` Tree

```text
lib/ichor/
├── application.ex                     # KEEP: OTP application entry point
├── repo.ex                            # KEEP: Ecto repository
├── notes.ex                           # KEEP: ETS-backed event annotations
│
├── runtime/
│   ├── supervisor.ex                  # NEW: replaces SystemSupervisor + ObservationSupervisor
│   ├── config.ex                      # NEW: application-level config/health
│   └── health.ex                      # NEW: cross-runtime health checks
│
├── events/
│   ├── runtime.ex                     # MOVE: Signals.Runtime -> Events.Runtime
│   ├── event.ex                       # KEEP: Signals.Event (signal emit/query actions)
│   ├── signals.ex                     # MOVE: Signals.Catalog -> Events.Signals
│   ├── catalog.ex                     # KEEP: Signals.Catalog (declarative catalog)
│   ├── query.ex                       # NEW: replaces ephemeral Ash read models
│   └── projections/
│       ├── attention.ex               # MOVE: Archon.SignalManager -> Events.Projections.Attention
│       ├── decision_log.ex            # MOVE: Mesh.DecisionLog -> Events.Projections.DecisionLog
│       ├── messages.ex                # MOVE: Observability.Message -> Events.Projections.Messages
│       ├── topology.ex                # MOVE: Mesh.CausalDAG -> Events.Projections.Topology
│       └── traces.ex                  # MOVE: ProtocolTracker -> Events.Projections.Traces
│
├── fleet/
│   ├── runtime.ex                     # MOVE: Control.FleetSupervisor -> Fleet.Runtime
│   ├── agent_process.ex               # MOVE: Control.AgentProcess -> Fleet.AgentProcess
│   ├── launcher.ex                    # MERGE: AgentLaunch + TeamLaunch + Registration + Cleanup
│   ├── query.ex                       # NEW: replaces Control.Agent + Control.Team read actions
│   ├── host_registry.ex               # MOVE: Control.HostRegistry -> Fleet.HostRegistry
│   └── blueprints/
│       ├── blueprint.ex               # MOVE: Control.Blueprint -> Fleet.Blueprints.Blueprint
│       ├── presets.ex                 # MOVE: Control.Presets -> Fleet.Blueprints.Presets
│       └── builder.ex                 # MOVE: Control.TeamSpecBuilder -> Fleet.Blueprints.Builder
│
├── projects/
│   ├── runtime.ex                     # KEEP: Projects.Runtime (lifecycle supervisor)
│   ├── run_manager.ex                 # MERGE: Runner + Spawn + Scheduler + Janitor + CompletionHandler
│   ├── query.ex                       # NEW: replaces PipelineMonitor + Project read actions
│   ├── graph.ex                       # KEEP: PipelineGraph (pure DAG functions)
│   ├── schemas/
│   │   ├── project.ex                 # KEEP: Factory.Project (Ash resource)
│   │   ├── artifact.ex                # KEEP: Factory.Artifact (embedded)
│   │   ├── roadmap_item.ex            # KEEP: Factory.RoadmapItem (embedded)
│   │   ├── pipeline.ex                # KEEP: Factory.Pipeline (Ash resource)
│   │   ├── pipeline_task.ex           # KEEP: Factory.PipelineTask (Ash resource)
│   │   └── job.ex                     # MOVE: Infrastructure.CronJob -> Projects.Schemas.Job
│   ├── prompts/
│   │   ├── mes.ex                     # MOVE: Workshop.TeamPrompts -> Projects.Prompts.Mes
│   │   ├── genesis.ex                 # MOVE: Factory.PlanningPrompts -> Projects.Prompts.Genesis
│   │   └── dag.ex                     # KEEP: Workshop.PipelinePrompts -> Projects.Prompts.Dag
│   ├── ingest/
│   │   ├── project_brief.ex           # MOVE: Projects.ProjectIngestor -> Projects.Ingest.ProjectBrief
│   │   └── research.ex                # MOVE: Projects.ResearchIngestor -> Projects.Ingest.Research
│   └── build/
│       ├── scaffold.ex                # MOVE: Projects.SubsystemScaffold -> Projects.Build.Scaffold
│       └── loader.ex                  # MOVE: Projects.SubsystemLoader -> Projects.Build.Loader
│
├── memory/
│   ├── store.ex                       # MOVE: MemoryStore -> Memory.Store
│   ├── storage.ex                     # MOVE: MemoryStore.Storage -> Memory.Storage
│   └── persistence.ex                 # MOVE: MemoryStore.Persistence -> Memory.Persistence
│
├── transport/
│   ├── message_bus.ex                 # MOVE: Messages.Bus -> Transport.MessageBus
│   ├── cron.ex                        # MOVE: Infrastructure.CronScheduler -> Transport.Cron
│   ├── hitl.ex                        # MOVE: Infrastructure.HITLRelay -> Transport.HITL
│   ├── output_capture.ex              # MOVE: Infrastructure.OutputCapture -> Transport.OutputCapture
│   ├── tmux.ex                        # MOVE: Infrastructure.Tmux -> Transport.Tmux
│   ├── ssh_tmux.ex                    # KEEP: Infrastructure.SshTmux -> Transport.SshTmux
│   ├── mailbox.ex                     # MOVE: Infrastructure.Channels.MailboxAdapter -> Transport.Mailbox
│   ├── webhook_router.ex              # MOVE: Infrastructure.WebhookRouter -> Transport.WebhookRouter
│   └── webhook_delivery.ex            # MOVE: Infrastructure.WebhookDelivery -> Transport.WebhookDelivery
│
├── tools/
│   ├── domain.ex                      # KEEP: if AshAi requires domain module
│   ├── runtime.ex                     # MOVE: Tools.RuntimeOps -> Tools.Runtime
│   ├── projects.ex                    # MERGE: Tools.ProjectExecution + Tools.Genesis -> Tools.Projects
│   └── memory.ex                      # MERGE: Tools.AgentMemory + Tools.Archon.Memory -> Tools.Memory
│
├── tasks/
│   ├── board.ex                       # KEEP: Board (tasks.jsonl read/write adapter)
│   └── jsonl_store.ex                 # KEEP: JSONL persistence adapter
│
└── plugs/
    └── operator_auth.ex               # KEEP: operator auth header plug
```

---

## Deleted Modules (current -> gone)

| Current Module | Reason |
|----------------|--------|
| `Ichor.EventBuffer` | Absorbed into Events.Runtime |
| `Ichor.Signals.Buffer` | DELETE -- replaced by ETS in Events.Runtime |
| `Ichor.Signals.TaskProjection` | Ephemeral read model -- use Events.Query |
| `Ichor.Signals.ToolFailure` | Ephemeral read model -- use Events.Query |
| `Ichor.Signals.EntropyTracker` | Move to Events.Projections or DELETE |
| `Ichor.Observability.*` (all 5) | Ephemeral Ash read models. Replace with Events.Query |
| `Ichor.Control` (namespace) | DELETE namespace shell, absorb children into Fleet |
| `Ichor.Control.Views.Preparations.*` | DELETE -- pure presentation helpers absorbed |
| `Ichor.Control.TmuxHelpers` | Absorbed into Fleet.Launcher or Transport.Tmux |
| `Ichor.Control.AgentType` | DELETE or collapse into constants |
| `Ichor.Projects.LifecycleSupervisor` | DELETE -- absorbed into Projects.Runtime |
| `Ichor.Projects.DateUtils` | DELETE -- absorb into callsite |
| `Ichor.Projects.ProjectStage` | Move to web presenter/query layer |
| `Ichor.Archon.SignalManager` | MOVE to Events.Projections.Attention |
| `Ichor.Mesh.DecisionLog.Helpers` | Absorbed into DecisionLog |
| `Ichor.Gateway.SchemaInterceptor` | Absorbed into webhook/router ingress |
| `Ichor.SystemSupervisor` | REPLACED by Runtime.Supervisor |
| `Ichor.ObservationSupervisor` | ABSORBED into Runtime.Supervisor |

---

## Summary Table

| Status | Count | Notes |
|--------|-------|-------|
| KEEP (no move) | ~18 | Core Ash resources, repo, application |
| MOVE (rename only) | ~25 | Same logic, new namespace |
| MERGE (combine N->1) | ~20 | Small lifecycle helpers combined |
| NEW | ~8 | Query modules, Runtime.Supervisor, Builder |
| DELETE | ~20 | Ephemeral Ash read models, Preparations, wrappers |
| **Target total** | **~55** | Down from 127 |

---

## Current-to-Target Module Mapping

### Supervisors

| Current | Target |
|---------|--------|
| `Ichor.Application` | `application.ex` (keep) |
| `Ichor.SystemSupervisor` | `Ichor.Runtime.Supervisor` |
| `Ichor.ObservationSupervisor` | absorbed into `Ichor.Runtime.Supervisor` |
| `Ichor.Mesh.Supervisor` | absorbed into `Ichor.Runtime.Supervisor` or `Ichor.Events.Runtime` |
| `Ichor.Projects.Runtime` | `Ichor.Projects.Runtime` (keep) |
| `Ichor.Control.FleetSupervisor` | `Ichor.Fleet.Runtime` |

### Events / Signals / Mesh

| Current | Target |
|---------|--------|
| `Ichor.Events.Runtime` | `Ichor.Events.Runtime` |
| `Ichor.Signals.Runtime` | `Ichor.Events.Runtime` (merge) |
| `Ichor.Signals.Event` | `Ichor.Events.Event` |
| `Ichor.Signals.Catalog` | `Ichor.Events.Catalog` |
| `Ichor.Signals.EventStream` | `Ichor.Events.Runtime` (absorbed) -- rename to EventStore conceptually |
| `Ichor.Signals.EventBridge` | `Ichor.Events.Projections.Topology` (split) |
| `Ichor.Signals.AgentWatchdog` | `Ichor.Fleet.Runtime` (fleet concern) |
| `Ichor.Signals.FromAsh` | keep if Ash notifiers still needed |
| `Ichor.Signals.ProtocolTracker` | `Ichor.Events.Projections.Traces` |
| `Ichor.Signals.EntropyTracker` | `Ichor.Events.Projections.Topology` or DELETE |
| `Ichor.Signals.Bus` | `Ichor.Transport.MessageBus` |
| `Ichor.Signals.Buffer` | DELETE |
| `Ichor.Signals.TaskProjection` | `Ichor.Events.Query` |
| `Ichor.Signals.ToolFailure` | `Ichor.Events.Query` |
| `Ichor.Mesh.CausalDAG` | `Ichor.Events.Projections.Topology` |
| `Ichor.Mesh.DecisionLog` | `Ichor.Events.Projections.DecisionLog` |
| `Ichor.Archon.SignalManager` | `Ichor.Events.Projections.Attention` |

### Fleet / Control

| Current | Target |
|---------|--------|
| `Ichor.Control.FleetSupervisor` | `Ichor.Fleet.Runtime` |
| `Ichor.Control.AgentProcess` | `Ichor.Fleet.AgentProcess` |
| `Ichor.Control.TeamSupervisor` | absorbed into `Ichor.Fleet.Runtime` |
| `Ichor.Control.HostRegistry` | `Ichor.Fleet.HostRegistry` |
| `Ichor.Control.Blueprint` | `Ichor.Fleet.Blueprints.Blueprint` |
| `Ichor.Control.Presets` | `Ichor.Fleet.Blueprints.Presets` |
| `Ichor.Control.TeamSpecBuilder` | `Ichor.Fleet.Blueprints.Builder` |
| `Ichor.Infrastructure.AgentProcess` | `Ichor.Fleet.AgentProcess` |
| `Ichor.Infrastructure.AgentLaunch` | `Ichor.Fleet.Launcher` |
| `Ichor.Infrastructure.TeamLaunch` | `Ichor.Fleet.Launcher` |
| `Ichor.Infrastructure.Registration` | absorbed into `Ichor.Fleet.Launcher` |
| `Ichor.Infrastructure.Cleanup` | absorbed into `Ichor.Fleet.Launcher` |
| `Ichor.Infrastructure.AgentSpec` | struct inside `Ichor.Fleet.Launcher` |
| `Ichor.Infrastructure.TeamSpec` | struct inside `Ichor.Fleet.Launcher` |

### Projects / Factory

| Current | Target |
|---------|--------|
| `Ichor.Factory.Project` | `Ichor.Projects.Schemas.Project` |
| `Ichor.Factory.Pipeline` | `Ichor.Projects.Schemas.Pipeline` |
| `Ichor.Factory.PipelineTask` | `Ichor.Projects.Schemas.PipelineTask` |
| `Ichor.Factory.Artifact` | `Ichor.Projects.Schemas.Artifact` |
| `Ichor.Factory.RoadmapItem` | `Ichor.Projects.Schemas.RoadmapItem` |
| `Ichor.Factory.Runner` | `Ichor.Projects.RunManager` |
| `Ichor.Factory.Spawn` | absorbed into `Ichor.Projects.RunManager` |
| `Ichor.Factory.MesScheduler` | Oban cron worker (DELETE GenServer) |
| `Ichor.Factory.PipelineMonitor` | `Ichor.Projects.Query` (pure module) + Oban cron |
| `Ichor.Factory.PlanningPrompts` | `Ichor.Projects.Prompts.Genesis` |
| `Ichor.Workshop.TeamPrompts` | `Ichor.Projects.Prompts.Mes` |
| `Ichor.Workshop.PipelinePrompts` | `Ichor.Projects.Prompts.Dag` |
| `Ichor.Workshop.TeamSpec` | `Ichor.Fleet.Blueprints.Builder` (pure compile) |
| `Ichor.Factory.Floor` | keep as action surface, extract view helpers |
| `Ichor.Factory.PipelineGraph` | `Ichor.Projects.Graph` |
| `Ichor.Factory.PipelineCompiler` | absorbed into `Ichor.Projects.RunManager` |

### Transport / Gateway

| Current | Target |
|---------|--------|
| `Ichor.Signals.Bus` | `Ichor.Transport.MessageBus` |
| `Ichor.Infrastructure.Tmux` | `Ichor.Transport.Tmux` |
| `Ichor.Infrastructure.TmuxDiscovery` | `Ichor.Fleet.Runtime` or `Ichor.Transport.Tmux` |
| `Ichor.Infrastructure.OutputCapture` | `Ichor.Transport.OutputCapture` |
| `Ichor.Infrastructure.CronScheduler` | `Ichor.Transport.Cron` |
| `Ichor.Infrastructure.HITLRelay` | `Ichor.Transport.HITL` |
| `Ichor.Infrastructure.WebhookRouter` | `Ichor.Transport.WebhookRouter` |
| `Ichor.Infrastructure.WebhookDelivery` | `Ichor.Transport.WebhookDelivery` |

### Memory

| Current | Target |
|---------|--------|
| `Ichor.MemoryStore` | `Ichor.Memory.Store` |
| `Ichor.MemoryStore.Storage` | `Ichor.Memory.Storage` |
| `Ichor.MemoryStore.Persistence` | `Ichor.Memory.Persistence` |
| `Ichor.Archon.MemoriesClient` | `Ichor.Memory` adapter or `Ichor.Tools.Memory` |
| `Ichor.MemoriesBridge` | `Ichor.Memory.Bridge` or `Ichor.Projects.Ingest.Research` |

---

## Implementation Phases (from codex target structure)

### Phase 1 -- Query modules (no process changes)
- Create `Events.Query` and `Fleet.Query`
- Replace ephemeral Ash resource callers with query function calls
- Delete `Signals.Buffer`, `Observability.*` preparations, `EventBuffer`

### Phase 2 -- Fleet launcher consolidation
- Create `Fleet.Launcher` absorbing AgentLaunch + TeamLaunch + Registration + Cleanup
- Move tmux helpers into `Transport.Tmux`
- Create `Fleet.Blueprints.Builder` from Workshop.TeamSpec (pure compile, no mode knowledge)

### Phase 3 -- Projects run manager
- Create `Projects.RunManager` absorbing Runner + Spawn + Scheduler + Janitor + CompletionHandler
- Replace MesScheduler GenServer with Oban cron worker
- Replace PipelineMonitor GenServer with `Projects.Query` + Oban cron workers

### Phase 4 -- Transport consolidation
- Move Bus into `Transport.MessageBus`
- Move all channels/adapters into `Transport.*`
- Move decision log/topology/traces into `Events.Projections.*`

### Phase 5 -- Final cleanup
- Shrink tool modules to match new runtime boundaries
- Simplify top-level supervision to `Runtime.Supervisor`
- Delete all remaining namespace shells (`Control`, `Observability`, `Gateway`)
