# Target `lib/ichor` Structure

## Goal

The target structure should reflect actual runtime boundaries rather than historical naming layers. The design below keeps features intact while aggressively reducing module count, wrapper layers, and cross-folder ambiguity.

## Target principles

- one folder per real runtime boundary
- plain query/projection modules for ephemeral state
- Ash resources only for durable records
- transport adapters separated from event projections
- prompts kept next to the runtime that uses them
- supervisors aligned with failure domains, not conceptual brands

## Proposed folder tree

```text
lib/ichor
├── application.ex
├── repo.ex
├── runtime
│   ├── supervisor.ex
│   ├── config.ex
│   └── health.ex
├── events
│   ├── runtime.ex
│   ├── event.ex
│   ├── signals.ex
│   ├── catalog.ex
│   ├── query.ex
│   └── projections
│       ├── attention.ex
│       ├── decision_log.ex
│       ├── messages.ex
│       ├── topology.ex
│       └── traces.ex
├── fleet
│   ├── runtime.ex
│   ├── agent_process.ex
│   ├── launcher.ex
│   ├── query.ex
│   ├── host_registry.ex
│   └── blueprints
│       ├── blueprint.ex
│       ├── presets.ex
│       └── builder.ex
├── projects
│   ├── runtime.ex
│   ├── run_manager.ex
│   ├── query.ex
│   ├── graph.ex
│   ├── schemas
│   │   ├── project.ex
│   │   ├── node.ex
│   │   ├── artifact.ex
│   │   ├── roadmap_item.ex
│   │   ├── run.ex
│   │   └── job.ex
│   ├── prompts
│   │   ├── mes.ex
│   │   ├── genesis.ex
│   │   └── dag.ex
│   ├── ingest
│   │   ├── project_brief.ex
│   │   └── research.ex
│   └── build
│       ├── scaffold.ex
│       └── loader.ex
├── memory
│   ├── store.ex
│   ├── storage.ex
│   └── persistence.ex
├── transport
│   ├── message_bus.ex
│   ├── cron.ex
│   ├── hitl.ex
│   ├── output_capture.ex
│   ├── tmux.ex
│   ├── ssh_tmux.ex
│   ├── mailbox.ex
│   ├── webhook_router.ex
│   └── webhook_delivery.ex
├── tools
│   ├── domain.ex
│   ├── runtime.ex
│   ├── projects.ex
│   └── memory.ex
├── tasks
│   ├── board.ex
│   └── jsonl_store.ex
├── notes.ex
└── plugs
    └── operator_auth.ex
```

## What this structure means

## `runtime/`

This folder should contain only application-level process wiring and cross-runtime health/config concerns.

It replaces:

- `Ichor.SystemSupervisor`
- `Ichor.ObservationSupervisor`
- much of the conceptual weight currently placed on subsystem-specific supervisors

## `events/`

This is the canonical source for:

- hook event ingestion
- session liveness
- event querying
- derived observability projections

It absorbs current code from:

- `Ichor.Events.*`
- `Ichor.Signals.*`
- `Ichor.Observability.*` except any truly durable schemas kept for compatibility
- `Ichor.EventBuffer`
- most of `Ichor.Gateway.EventBridge`
- `Ichor.ProtocolTracker`
- `Ichor.Archon.SignalManager`
- parts of `Ichor.Archon.TeamWatchdog`
- message/error/task/session read-model preparations

## `fleet/`

This is the canonical source for:

- agent and team lifecycle
- process registration
- launching tmux-backed agents
- fleet querying
- saved blueprints

It absorbs current code from:

- `Ichor.Control.*`
- `Ichor.Control.Lifecycle.*`
- `Ichor.Control.Views.*`
- parts of `Ichor.Gateway.AgentRegistry.*`

## `projects/`

This is the canonical source for:

- durable project records
- run/job orchestration
- prompt/spec generation
- project-brief ingestion
- subsystem load/build steps

It absorbs current code from:

- most of `Ichor.Projects.*`
- parts of `Ichor.Archon.TeamWatchdog`

The persistent records remain in `schemas/`. Everything orchestration-related moves to `runtime.ex`, `run_manager.ex`, and `query.ex`.

## `memory/`

This is a straightforward rename of `memory_store` into a clearer boundary. The current split is already good.

## `transport/`

This folder holds real IO boundaries only:

- tmux
- ssh
- mailbox
- webhook
- operator HITL
- scheduled delivery
- output capture
- message sending

This absorbs current code from:

- `Ichor.Messages.Bus`
- `Ichor.Infrastructure.Channels.*`
- `Ichor.Gateway.Cron*`
- `Ichor.Gateway.HITL*`
- `Ichor.Gateway.OutputCapture`
- `Ichor.Gateway.Webhook*`

It should not hold event projections like entropy or decision logs.

## `tools/`

Keep the tool surface small and aligned to underlying service areas:

- runtime/fleet tools
- project tools
- memory tools

This replaces:

- `Ichor.Tools`
- `Ichor.Tools.RuntimeOps`
- `Ichor.Tools.ProjectExecution`
- `Ichor.Tools.AgentMemory`
- `Ichor.Tools.Genesis`
- `Ichor.Tools.Archon.Memory`

Potentially `domain.ex` remains only if AshAi requires a domain module.

## Current-to-target mapping

## Top-level and supervisors

- `Ichor.Application` -> keep as `application.ex`
- `Ichor.SystemSupervisor` -> `Ichor.Runtime.Supervisor`
- `Ichor.ObservationSupervisor` -> absorbed into `Ichor.Runtime.Supervisor`

## Events, signals, observability, mesh

- `Ichor.Events.Runtime` -> `Ichor.Events.Runtime`
- `Ichor.Events.Event` -> `Ichor.Events.Event`
- `Ichor.EventBuffer` -> delete
- `Ichor.Signals.Runtime` -> `Ichor.Events.Signals`
- `Ichor.Signals.Catalog` -> `Ichor.Events.Catalog`
- `Ichor.Signals.Buffer` -> delete
- `Ichor.Signals.Event` -> likely absorb into `Ichor.Events.Event` or delete if duplicate
- `Ichor.Signals.FromAsh` -> keep only if durable schemas still need Ash notifiers
- `Ichor.Observability` -> delete or replace with query namespace
- `Ichor.Observability.Message` -> `Ichor.Events.Projections.Messages` or `Ichor.Events.Query`
- `Ichor.Observability.Task` -> `Ichor.Events.Query`
- `Ichor.Observability.Error` -> `Ichor.Events.Query`
- `Ichor.Observability.Session` -> `Ichor.Events.Query`
- `Ichor.Observability.Preparations.*` -> delete
- `Ichor.Gateway.EventBridge` -> split into:
  - `Ichor.Events.Projections.DecisionLog`
  - `Ichor.Events.Projections.Topology`
- `Ichor.ProtocolTracker` -> `Ichor.Events.Projections.Traces`
- `Ichor.Archon.SignalManager` -> `Ichor.Events.Projections.Attention`
- `Ichor.Mesh.DecisionLog` -> `Ichor.Events.Projections.DecisionLog`
- `Ichor.Mesh.DecisionLog.Helpers` -> absorbed
- `Ichor.Mesh.CausalDAG` -> `Ichor.Events.Projections.Topology` or retained as `Ichor.Events.Topology`

## Fleet/control

- `Ichor.Control` -> delete
- `Ichor.Control.AgentProcess` -> `Ichor.Fleet.AgentProcess`
- `Ichor.Control.FleetSupervisor` -> `Ichor.Fleet.Runtime`
- `Ichor.Control.TeamSupervisor` -> absorbed into `Ichor.Fleet.Runtime`
- `Ichor.Control.Agent` -> `Ichor.Fleet.Query` plus `Ichor.Fleet.Runtime`
- `Ichor.Control.Team` -> `Ichor.Fleet.Query` plus `Ichor.Fleet.Runtime`
- `Ichor.Control.HostRegistry` -> `Ichor.Fleet.HostRegistry`
- `Ichor.Control.Blueprint` -> `Ichor.Fleet.Blueprints.Blueprint`
- `Ichor.Control.Presets` -> `Ichor.Fleet.Blueprints.Presets`
- `Ichor.Control.TeamSpecBuilder` -> `Ichor.Fleet.Blueprints.Builder`
- `Ichor.Control.BlueprintState` -> absorbed into blueprints builder/presets
- `Ichor.Control.TmuxHelpers` -> absorbed into launcher or presets
- `Ichor.Control.AgentType` -> delete or collapse into constants
- `Ichor.Control.Views.Preparations.*` -> delete

## Fleet lifecycle internals

- `Ichor.Control.Lifecycle.AgentLaunch` -> `Ichor.Fleet.Launcher`
- `Ichor.Control.Lifecycle.TeamLaunch` -> `Ichor.Fleet.Launcher`
- `Ichor.Control.Lifecycle.AgentSpec` -> nested struct in `Ichor.Fleet.Launcher`
- `Ichor.Control.Lifecycle.TeamSpec` -> nested struct in `Ichor.Fleet.Launcher`
- `Ichor.Control.Lifecycle.Registration` -> absorbed into launcher/runtime
- `Ichor.Control.Lifecycle.Cleanup` -> absorbed into launcher/runtime
- `Ichor.Control.Lifecycle.TmuxLauncher` -> `Ichor.Transport.Tmux`
- `Ichor.Control.Lifecycle.TmuxScript` -> helper inside launcher or `Ichor.Transport.Tmux`

## Projects

- `Ichor.Projects` -> optional `Ichor.Projects.Domain` if Ash is still wanted, otherwise delete
- `Ichor.Projects.Project` -> `Ichor.Projects.Schemas.Project`
- `Ichor.Projects.Node` -> `Ichor.Projects.Schemas.Node`
- `Ichor.Projects.Artifact` -> `Ichor.Projects.Schemas.Artifact`
- `Ichor.Projects.RoadmapItem` -> `Ichor.Projects.Schemas.RoadmapItem`
- `Ichor.Projects.Run` -> `Ichor.Projects.Schemas.Run`
- `Ichor.Projects.Job` -> `Ichor.Projects.Schemas.Job`
- `Ichor.Projects.Runner` -> `Ichor.Projects.RunManager`
- `Ichor.Projects.Runtime` -> `Ichor.Projects.Runtime`
- `Ichor.Projects.Spawn` -> absorbed into runtime/run manager
- `Ichor.Projects.TeamSpec` -> absorbed into run manager/prompts
- `Ichor.Projects.Scheduler` -> absorbed into runtime
- `Ichor.Projects.Janitor` -> absorbed into runtime
- `Ichor.Projects.CompletionHandler` -> absorbed into run manager
- `Ichor.Projects.ProjectIngestor` -> `Ichor.Projects.Ingest.ProjectBrief`
- `Ichor.Projects.ResearchIngestor` -> `Ichor.Projects.Ingest.Research`
- `Ichor.Projects.ResearchStore` -> adapter under `projects/ingest` or `build`
- `Ichor.Projects.Graph` -> `Ichor.Projects.Graph`
- `Ichor.Projects.ModePrompts` -> `Ichor.Projects.Prompts.Genesis`
- `Ichor.Projects.TeamPrompts` -> `Ichor.Projects.Prompts.Mes`
- `Ichor.Projects.DagPrompts` -> `Ichor.Projects.Prompts.Dag`
- `Ichor.Projects.PipelineStage` -> move to web presenter/query layer
- `Ichor.Projects.DateUtils` -> absorb
- `Ichor.Projects.SubsystemLoader` -> `Ichor.Projects.Build.Loader`
- `Ichor.Projects.SubsystemScaffold` -> `Ichor.Projects.Build.Scaffold`
- `Ichor.Projects.Job.Preparations.FilterAvailable` -> absorb into query/action
- `Ichor.Projects.Job.Changes.SyncRunProcess` -> absorb into run manager
- `Ichor.Projects.LifecycleSupervisor` -> delete

## Memory

- `Ichor.MemoryStore` -> `Ichor.Memory.Store`
- `Ichor.MemoryStore.Storage` -> `Ichor.Memory.Storage`
- `Ichor.MemoryStore.Persistence` -> `Ichor.Memory.Persistence`
- `Ichor.MemoriesBridge` -> either `Ichor.Memory.Bridge` or move under `projects/ingest` depending on actual ownership
- `Ichor.Archon.MemoriesClient` -> adapter under `memory/` or `tools/`

## Transport/gateway/messages

- `Ichor.Messages.Bus` -> `Ichor.Transport.MessageBus`
- `Ichor.Infrastructure.Channels.Tmux` -> `Ichor.Transport.Tmux`
- `Ichor.Infrastructure.Channels.SshTmux` -> `Ichor.Transport.SshTmux`
- `Ichor.Infrastructure.Channels.MailboxAdapter` -> `Ichor.Transport.Mailbox`
- `Ichor.Infrastructure.Channels.WebhookAdapter` -> `Ichor.Transport.Webhook`
- `Ichor.Gateway.CronScheduler` -> `Ichor.Transport.Cron`
- `Ichor.Infrastructure.CronJob` -> `Ichor.Transport.CronJob` or merge into `Cron`
- `Ichor.Gateway.HITLRelay` -> `Ichor.Transport.HITL`
- `Ichor.Observability.HITLInterventionEvent` -> keep only if persisted audit records are needed
- `Ichor.Gateway.WebhookRouter` -> `Ichor.Transport.WebhookRouter`
- `Ichor.Infrastructure.WebhookDelivery` -> `Ichor.Transport.WebhookDelivery`
- `Ichor.Gateway.OutputCapture` -> `Ichor.Transport.OutputCapture`
- `Ichor.Gateway.TmuxDiscovery` -> likely `Ichor.Fleet.Runtime` or `Ichor.Transport.Tmux`
- `Ichor.Gateway.SchemaInterceptor` -> absorb into webhook/router ingress
- `Ichor.Gateway.EntropyTracker` -> move to `events/projections` or delete

## Tools

- `Ichor.Tools` -> `Ichor.Tools.Domain`
- `Ichor.Tools.RuntimeOps` -> `Ichor.Tools.Runtime`
- `Ichor.Tools.ProjectExecution` -> `Ichor.Tools.Projects`
- `Ichor.Tools.AgentMemory` -> `Ichor.Tools.Memory`
- `Ichor.Tools.Archon.Memory` -> absorb into `Ichor.Tools.Memory`
- `Ichor.Tools.Genesis` -> fold into `Ichor.Tools.Projects` unless AshAi ergonomics argue otherwise

## Suggested final module count

This target structure suggests roughly:

- 45-60 modules total

That assumes:

- ephemeral Ash resources are deleted
- most preparations are deleted
- sidecar subscribers are folded into runtimes/projections
- helper-only tiny lifecycle modules are merged

## Suggested implementation phases

## Phase 1

- create `events/query.ex` and `fleet/query.ex`
- replace ephemeral Ash resource callers
- delete preparations and `EventBuffer`

## Phase 2

- create `fleet/launcher.ex`
- absorb lifecycle helpers
- move transport-specific tmux helpers into `transport/`

## Phase 3

- create `projects/run_manager.ex`
- absorb scheduler/janitor/completion/ingestors
- reduce `Projects.LifecycleSupervisor`

## Phase 4

- move message bus and adapters into `transport/`
- move decision log/topology/traces/attention into `events/projections`

## Phase 5

- shrink tool modules to match the new runtime boundaries
- simplify top-level supervision

## Non-goals

- do not re-expand the code under new names
- do not preserve old subsystem branding if it no longer matches execution boundaries
- do not keep Ash resources for ephemeral read models just because the UI currently queries through Ash

## Bottom line

The target structure should be runtime-first:

- `events`
- `fleet`
- `projects`
- `memory`
- `transport`
- `tools`

Everything else is secondary. If a module does not clearly belong to one of those boundaries and does not own durable state or a real IO edge, it is probably a candidate for deletion or absorption.
