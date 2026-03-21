# `lib/ichor` Simplification Audit

Research-only audit of `lib/ichor`.
No runtime code was modified.

## Executive Summary

`lib/ichor` currently spans roughly 220 Elixir modules and about 24k LOC. The real system is much smaller than the names imply. Most of the folder is not core behavior. It is:

- wrapper Ash resources that expose one or two actions
- orchestration facades that forward to one deeper module
- near-identical GenServers for different “named” run types
- duplicate routing and projection pipelines that process the same events in different shapes
- pure helper modules that exist only because the surrounding design is over-sliced

The codebase does have real complexity, but it is concentrated in a small number of engines:

- fleet runtime and tmux lifecycle
- run lifecycle and job execution
- event ingestion and projection
- memory storage and persistence
- Ash resources that represent actual persisted entities

My main conclusion is:

- more than half of the orchestration, tool-surface, and façade modules can be removed
- more than half of all `lib/ichor` modules can be removed only if the team is willing to collapse the Ash tool surface aggressively and stop naming every variant as its own subsystem
- the highest-value work is not deleting resource schemas; it is collapsing duplicated control flow

The correct redesign is not “rename better”. It is:

- one message bus
- one event pipeline
- one generic run runtime
- one generic team spec builder with templates
- a much smaller MCP tool surface

## What The Code Really Is

Behind the vocabulary, the runtime mostly reduces to this:

1. Events arrive and are buffered.
2. Events update live agent metadata and UI projections.
3. Messages are delivered to BEAM mailboxes and tmux.
4. Some workflows spawn tmux-backed teams.
5. Some workflows monitor those teams until completion.

Everything beyond that is mostly shape duplication.

## High-Confidence Findings

### 1. Two messaging systems exist for one problem

`Ichor.MessageRouter` and `Ichor.Gateway.Router` both:

- parse target patterns like `team:*`, `role:*`, `session:*`, `agent:*`
- resolve recipients from live agent state
- deliver through mailbox or tmux-like channels
- emit audit/protocol side effects

The duplication is explicit in comments inside both modules. That is not a harmless implementation detail. It means the code already knows it has two routing systems.

Files:

- `lib/ichor/message_router.ex`
- `lib/ichor/gateway/router.ex`
- `lib/ichor/gateway/router/event_ingest.ex`

Recommended simplification:

- keep one bus only
- make “event ingest” a function on that bus or on a single event runtime module
- treat channel adapters as implementation details of the one bus

High-confidence removals by merge:

- `Ichor.Gateway.Router`
- `Ichor.Gateway.Router.EventIngest`
- `Ichor.Gateway.Envelope`
- likely `Ichor.MessageRouter` or its public shape, depending on which API is retained

### 2. Three run runtimes share the same lifecycle skeleton

`BuildRunner`, `PlanRunner`, and `RunProcess` are variants of the same OTP pattern:

- register under `Registry`
- monitor tmux liveness
- subscribe to signals
- stop on coordinator/operator completion signal
- emit lifecycle signals
- tear down the tmux-backed team

The differences are mostly policy knobs:

- completion predicate
- periodic checks
- session prefix
- optional deadline / health logic

Files:

- `lib/ichor/projects/build_runner.ex`
- `lib/ichor/projects/plan_runner.ex`
- `lib/ichor/projects/run_process.ex`
- `lib/ichor/projects/runner_registry.ex`

Recommended simplification:

- one generic `Ichor.Projects.Runner` GenServer
- one `%RunMode{}` or config map describing policy per mode
- mode-specific callbacks only for genuinely different behavior

High-confidence removals by merge:

- `Ichor.Projects.BuildRunner`
- `Ichor.Projects.PlanRunner`
- `Ichor.Projects.RunProcess`
- `Ichor.Projects.RunnerRegistry`

### 3. The supervisor tree is padded with single-child wrappers

`PlanSupervisor` and `ExecutionSupervisor` are both named wrappers around one `DynamicSupervisor`. `RunSupervisor` is not a supervisor at all; it is a facade around `DynamicSupervisor.start_child/2` and `Registry`.

Files:

- `lib/ichor/projects/plan_supervisor.ex`
- `lib/ichor/projects/execution_supervisor.ex`
- `lib/ichor/projects/run_supervisor.ex`

Recommended simplification:

- start the dynamic supervisors directly from `Ichor.Application` or one project supervisor
- delete the facade and call `DynamicSupervisor` directly from the unified run runtime

High-confidence removals:

- `Ichor.Projects.PlanSupervisor`
- `Ichor.Projects.ExecutionSupervisor`
- `Ichor.Projects.RunSupervisor`

### 4. Project orchestration is split into too many nouns

The `projects` runtime is fragmented into small modules that all manipulate the same state machine:

- discovery
- catalog
- dag analysis
- actions
- health report
- health checker
- team lifecycle
- team cleanup
- spawner
- mode spawner
- three team spec builders

Many of these are individually reasonable. Together they create indirection without new boundaries.

Files:

- `lib/ichor/projects/runtime.ex`
- `lib/ichor/projects/catalog.ex`
- `lib/ichor/projects/discovery.ex`
- `lib/ichor/projects/dag_analysis.ex`
- `lib/ichor/projects/actions.ex`
- `lib/ichor/projects/health_checker.ex`
- `lib/ichor/projects/health_report.ex`
- `lib/ichor/projects/team_lifecycle.ex`
- `lib/ichor/projects/team_cleanup.ex`
- `lib/ichor/projects/mode_spawner.ex`
- `lib/ichor/projects/spawner.ex`
- `lib/ichor/projects/team_spec_builder.ex`
- `lib/ichor/projects/genesis_team_spec_builder.ex`
- `lib/ichor/projects/dag_team_spec_builder.ex`

Recommended simplification:

- `Projects.Runtime` should own discovery, active project tracking, task refresh, and corrective actions
- one `Projects.Spawn` should launch all run kinds
- one `Projects.TeamSpec` builder should accept a preset plus prompt/template callbacks
- one `Projects.Health` should contain both pure analysis and optional external-script adapter
- one cleanup path should exist, not a MES-specific wrapper plus generic cleanup plus janitor

High-confidence removals by merge:

- `Ichor.Projects.Catalog`
- `Ichor.Projects.Discovery`
- `Ichor.Projects.DagAnalysis`
- `Ichor.Projects.Actions`
- `Ichor.Projects.HealthChecker`
- `Ichor.Projects.HealthReport`
- `Ichor.Projects.TeamLifecycle`
- `Ichor.Projects.TeamCleanup`
- `Ichor.Projects.ModeSpawner`
- `Ichor.Projects.Spawner`
- two of the three specialized team spec builders

### 5. Control-plane wrappers add names, not leverage

Several `control` modules are thin veneers:

- `Ichor.Control.Lifecycle` is only a `defdelegate`
- `Ichor.Control.Lookup` is a tiny lookup helper over `Agent.all!()`
- `Ichor.Control.RuntimeQuery` and `RuntimeView` are dashboard formatting helpers split from the actual readers
- `Ichor.Control.Persistence` wraps a small amount of blueprint load/save flow

Files:

- `lib/ichor/control/lifecycle.ex`
- `lib/ichor/control/lookup.ex`
- `lib/ichor/control/runtime_query.ex`
- `lib/ichor/control/runtime_view.ex`
- `lib/ichor/control/persistence.ex`

Recommended simplification:

- move dashboard-only formatting near the dashboard or one `Control.Query` module
- inline `Lifecycle`
- fold `Lookup` into the reader/query module
- keep persistence helpers only if they centralize validations, otherwise inline into the blueprint resource boundary

High-confidence removals:

- `Ichor.Control.Lifecycle`
- `Ichor.Control.Lookup`
- `Ichor.Control.RuntimeQuery`
- `Ichor.Control.RuntimeView`
- possibly `Ichor.Control.Persistence`

### 6. Tool surface is drastically over-expanded

There are 25 tool modules under `tools`, plus `Tools.AgentControl` and `Tools.MapUtils`, plus the domain module that manually lists every resource and every tool.

Most tool modules do one of these:

- define one or two Ash actions
- convert arguments
- call one runtime/resource function
- map the result to a string-keyed map

This is the single biggest module-count inflation point in the tree.

Files:

- `lib/ichor/tools.ex`
- `lib/ichor/tools/agent/*.ex`
- `lib/ichor/tools/archon/*.ex`
- `lib/ichor/tools/agent_control.ex`
- `lib/ichor/tools/map_utils.ex`

Current shape:

- 12 agent tool resources
- 9 archon tool resources
- 2 utility modules
- 1 domain registry module

Recommended simplification:

- keep the tool names stable for MCP callers
- collapse the implementation into 3 to 5 resource modules at most
- group by real backend boundary, not by prose category

Suggested grouping:

- `Tools.AgentMessaging`
- `Tools.AgentMemory`
- `Tools.AgentExecution`
- `Tools.ArchonOps`
- `Tools.Genesis` if the Genesis artifact surface must stay separate

High-confidence removals by merge:

- at least 15 to 20 tool modules
- `Ichor.Tools.AgentControl`
- `Ichor.Tools.MapUtils`

Important note:

- this simplification can preserve every MCP tool name; the internal resource/module count does not need to mirror the external tool count

### 7. Event projection is duplicated across too many services

The system currently has several concurrent consumers of the same live event stream:

- `EventBuffer`
- `Gateway.EventBridge`
- `ProtocolTracker`
- `AgentWatchdog`
- `MemoriesBridge`
- `Projects.Runtime`
- `Control` preparations

Some of that is necessary. The problem is that several services also compute overlapping notions of:

- current session identity
- liveness
- “what happened recently”
- routing audit traces
- topology/projection state

Files:

- `lib/ichor/event_buffer.ex`
- `lib/ichor/gateway/event_bridge.ex`
- `lib/ichor/protocol_tracker.ex`
- `lib/ichor/agent_watchdog.ex`
- `lib/ichor/memories_bridge.ex`
- `lib/ichor/gateway/heartbeat_manager.ex`

Specific duplication:

- `AgentWatchdog` already emits heartbeats and handles stale agents
- `HeartbeatManager` separately tracks heartbeats and evictions
- `EventBridge` converts events into another internal log shape
- `ProtocolTracker` builds a second observability stream for message flow

Recommended simplification:

- one `EventRuntime` subscribes to raw events
- it owns session aliases, recent event cache, liveness, and projection fan-out
- secondary sinks like memories ingestion can subscribe to that normalized stream instead of rebuilding identity and trace state

High-confidence removals by merge:

- `Ichor.Gateway.HeartbeatManager`
- `Ichor.ProtocolTracker`
- `Ichor.Gateway.EventBridge`

Possible additional merge target:

- absorb parts of `AgentWatchdog` into the event runtime, keeping only pane scan policy separate if needed

### 8. MemoryStore is over-modular for its scale

`MemoryStore` plus five helper modules is not absurd, but it is still over-sliced relative to its behavior. The helpers are cohesive only because the GenServer API is broad.

Files:

- `lib/ichor/memory_store.ex`
- `lib/ichor/memory_store/blocks.ex`
- `lib/ichor/memory_store/recall.ex`
- `lib/ichor/memory_store/archival.ex`
- `lib/ichor/memory_store/persistence.ex`
- `lib/ichor/memory_store/tables.ex`

Recommended simplification:

- keep `MemoryStore`
- reduce helpers to:
  - `MemoryStore.Storage`
  - `MemoryStore.Persistence`
- keep table names and limits as module attributes on the owning module unless they truly need sharing

High-confidence removals by merge:

- 2 to 4 helper modules

## Modules That Look Fancy But Are Mostly Naming Layers

These are the strongest “remove first” candidates because they add almost no semantic protection:

- `Ichor.Control.Lifecycle`
- `Ichor.Projects.PlanSupervisor`
- `Ichor.Projects.ExecutionSupervisor`
- `Ichor.Projects.RunSupervisor`
- `Ichor.Projects.RunnerRegistry`
- `Ichor.Projects.TeamLifecycle`
- `Ichor.Projects.TeamCleanup`
- `Ichor.Control.Lookup`
- `Ichor.Tools.MapUtils`
- `Ichor.Tools.AgentControl`
- `Ichor.Gateway.Envelope`
- `Ichor.Gateway.IntentMapper`

## Modules That Should Probably Stay

These are real boundaries and should not be targeted first:

- `Ichor.Control.AgentProcess`
- `Ichor.Control.FleetSupervisor`
- `Ichor.Control.TeamSupervisor`
- `Ichor.Control.Lifecycle.TeamLaunch`
- `Ichor.Control.Lifecycle.AgentLaunch`
- `Ichor.EventBuffer` or its replacement
- `Ichor.MemoryStore` or its replacement
- `Ichor.Projects.Runtime` or its replacement
- persisted Ash resources such as `Project`, `Node`, `Run`, `Job`, `Adr`, `Feature`, `UseCase`, `Phase`, `Section`, `RoadmapTask`, `Subtask`

Reason:

- these modules correspond to actual runtime ownership, actual persisted state, or OTP process boundaries

## Proposed Target Architecture

### A. Fleet

Keep a small fleet core:

- `Ichor.Fleet.AgentProcess`
- `Ichor.Fleet.Supervisor`
- `Ichor.Fleet.TeamSupervisor`
- `Ichor.Fleet.Launch`

Collapse:

- lifecycle wrappers
- lookup/query/view formatting helpers
- duplicated stop/registration routing

### B. Projects

Keep one project runtime and one generic runner:

- `Ichor.Projects.Runtime`
- `Ichor.Projects.Runner`
- `Ichor.Projects.Spawn`
- `Ichor.Projects.TeamSpec`

Collapse:

- `BuildRunner`
- `PlanRunner`
- `RunProcess`
- `ModeSpawner`
- `Spawner`
- `TeamLifecycle`
- `TeamCleanup`
- `Catalog`
- `Discovery`
- `DagAnalysis`
- `Actions`
- `HealthChecker`
- `HealthReport`
- most specialized spec-builder duplication

### C. Events And Messaging

Keep:

- `Ichor.Events.Runtime`
- `Ichor.Messages.Bus`

Collapse:

- `MessageRouter`
- `Gateway.Router`
- `Gateway.Router.EventIngest`
- `Gateway.EventBridge`
- `ProtocolTracker`
- `HeartbeatManager`
- `Envelope`
- `IntentMapper`

### D. Tools

Keep a few backend-oriented resources, not dozens of category-oriented ones.

Collapse:

- 25 tool modules down to 3 to 5 modules
- preserve external tool names
- move mapping helpers into local private functions or shared presenters

## Expected Reduction

Conservative, high-confidence reduction without changing external behavior much:

- remove or merge roughly 55 to 75 modules

Aggressive but still realistic reduction if the MCP tool surface and run runtimes are properly unified:

- remove or merge roughly 90 to 120 modules

That aggressive number is where “more than half” becomes believable, but only if the team is willing to:

- collapse the tool resource fan-out
- stop giving each run variant its own lifecycle process stack
- stop keeping both gateway-routing and message-routing implementations alive

## Recommended Order Of Attack

### Phase 1: Delete trivial wrappers

Do first because risk is low and clarity improves immediately.

- remove `Control.Lifecycle`
- remove project supervisor wrappers
- remove `RunSupervisor`
- remove `RunnerRegistry`
- remove `Tools.MapUtils`
- remove `Tools.AgentControl`
- merge `Lookup` into the one module that actually uses it

### Phase 2: Unify messaging and event flow

Do second because it simplifies many downstream modules.

- choose one public message bus
- merge event ingest into the bus or one event runtime
- delete duplicated recipient resolution logic
- merge heartbeat/liveness ownership into one runtime

### Phase 3: Unify run lifecycle

Do third because it deletes a large amount of repeated OTP code.

- build one generic `Runner`
- express MES, Genesis, and DAG as mode configs
- keep only genuinely different completion or periodic policies as callbacks

### Phase 4: Collapse the tool surface

Do fourth because it drops module count fast after the runtime APIs are cleaner.

- keep MCP tool names
- reduce implementation modules drastically
- move formatting into local helpers instead of one-file-per-micro-surface

### Phase 5: Clean up memory store and remaining projections

Do last because this is tidy-up, not the main win.

## Design Rules For The Rewrite

- one feature should have one owning runtime module
- do not create a module just to rename a call chain
- do not create a GenServer variant when a mode/config would do
- do not create an Ash resource per tiny tool category
- presentation-only shaping should live near the presentation boundary
- event normalization should happen once
- routing target resolution should happen once

## Final Judgment

`lib/ichor` is not primarily suffering from lack of abstraction. It is suffering from too many abstractions at the wrong level.

The system has a workable core, but it is hidden behind a large amount of ceremonial module slicing. The highest-return simplification is to collapse duplicated control flow, not to micro-optimize individual functions.

If I had to summarize the whole audit in one sentence:

The codebase should be redesigned around a few state-owning runtimes and a few real boundaries, instead of a large vocabulary of small modules that mostly restate each other.
