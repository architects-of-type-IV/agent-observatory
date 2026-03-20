# `lib/ichor` Simplification Audit

## Executive summary

`lib/ichor` currently contains 127 modules and about 22.8k lines. The code is not large because the problem is inherently that large; it is large because the same handful of mechanisms are repeatedly wrapped in separate domains, resources, projections, supervisors, and “subsystems”.

The real system is much smaller than the namespace suggests:

- a signal bus
- an event/event-log runtime
- a fleet runtime for agents and tmux-backed sessions
- a project/run runtime for MES, Genesis, and DAG flows
- a memory store
- a small set of persistent schemas
- prompt builders
- a tool surface

Everything else is mostly one of:

- a compatibility shim
- an Ash wrapper around runtime state
- a projection module that reconstructs view models from ETS or event logs
- a single-purpose subscriber process
- a naming split where “MES”, “Genesis”, “DAG”, “gateway”, “mesh”, and “observability” are treated like separate architectures when they are mostly modes of the same runtime

The main conclusion is straightforward:

- more than half of the modules in `lib/ichor` can be removed without losing features
- the code should be reorganized around a few runtime-centric modules instead of many nouns
- the system should prefer plain Elixir query/service modules over Ash resources for ephemeral projections
- the event pipeline should have one canonical owner and a very small number of derived projections

If this refactor is done well, a realistic target is:

- reduce `lib/ichor` from 127 modules to roughly 45-60 modules
- reduce orchestration code by 35-50%
- keep all existing user-facing features
- make future changes cheaper because control flow becomes explicit instead of scattered across subscribers, preparations, and wrapper resources

## What the codebase is actually doing

The current folder structure implies many distinct subsystems:

- `control`
- `projects`
- `gateway`
- `signals`
- `events`
- `observability`
- `archon`
- `mesh`
- `messages`
- `memory_store`
- `tasks`

In practice, these collapse into four major behaviors:

1. Fleet runtime

- start agents
- register agents/teams
- talk to tmux/webhook/mailbox channels
- watch liveness and failures

2. Event runtime

- ingest hook events
- normalize/store them
- derive traces, topology, attention, logs, and UI projections

3. Project runtime

- persist project/run/job/node/artifact/roadmap data
- spawn run teams
- monitor run completion/failure/cleanup
- build prompts for MES/Genesis/DAG modes

4. Tool/memory surface

- expose MCP tools
- maintain per-agent memory

This means the existing module count is inflated by representation choices, not by irreducible complexity.

## High-confidence simplification thesis

### 1. The code has too many runtime projections dressed up as domains

The strongest simplification opportunity is removing Ash resources that do not represent durable domain records.

Examples:

- `Ichor.Control.Agent`
- `Ichor.Control.Team`
- `Ichor.Observability.Message`
- `Ichor.Observability.Task`
- `Ichor.Observability.Error`
- `Ichor.Observability.Session`
- associated `Preparations.*` modules

These modules mostly project runtime data from:

- `Registry`
- ETS tables
- `Ichor.Events.Runtime`
- filesystem state

They are not acting like durable entities with meaningful domain invariants. They are read models. Modeling them as Ash resources multiplies files and indirection:

- resource module
- preparation module
- sometimes helper readers
- domain registration
- code interface

This is a poor trade when the underlying source is already plain Elixir data.

Recommendation:

- keep Ash only for durable records that benefit from persistence and code interfaces
- replace ephemeral read models with plain query modules, for example:
  - `Ichor.Fleet.Query`
  - `Ichor.Events.Query`
  - `Ichor.Projects.Query`

### 2. Event ownership is fragmented across too many subscribers

The current event path is spread across:

- `Ichor.Events.Runtime`
- `Ichor.EventBuffer`
- `Ichor.Signals.Runtime`
- `Ichor.Signals.Buffer`
- `Ichor.Gateway.EventBridge`
- `Ichor.ProtocolTracker`
- `Ichor.Archon.SignalManager`
- `Ichor.Archon.TeamWatchdog`
- `Ichor.AgentWatchdog`
- `Ichor.Projects.ProjectIngestor`
- `Ichor.Projects.ResearchIngestor`
- `Ichor.Projects.CompletionHandler`

This is the single biggest structural problem.

The system has one central fact source: normalized events. But instead of one canonical runtime that owns derived state, many separate GenServers subscribe and each maintain a sliver of duplicate interpretation.

Symptoms:

- multiple modules subscribe to the same event stream
- multiple ETS/log buffers exist
- multiple modules transform the same events into different projections
- run lifecycle behavior is split between runner logic and external signal listeners

Recommendation:

- `Ichor.Events.Runtime` should be the canonical owner of event ingestion and derived state
- most current subscribers should become either:
  - functions called directly from the event runtime, or
  - lightweight pure projection modules with no GenServer

Only a few long-lived processes should remain:

- event runtime
- fleet runtime
- project runtime
- memory store

### 3. “MES”, “Genesis”, and “DAG” are modes, not separate architectures

This is already partially acknowledged in:

- `Ichor.Projects.Runner`
- `Ichor.Projects.Spawn`
- `Ichor.Projects.TeamSpec`
- unified `Artifact` and `RoadmapItem`

That direction is correct. The problem is that the code did not go far enough. The unification exists, but too many legacy-looking support modules remain around it:

- `Scheduler`
- `Janitor`
- `CompletionHandler`
- `ProjectIngestor`
- `ResearchIngestor`
- `LifecycleSupervisor`
- multiple prompt modules
- multiple cleanup helpers
- multiple run supervisors

The design should fully commit to:

- one project orchestration runtime
- one run record model
- one run manager
- one spawn/teardown path
- one prompt/spec composition pipeline

### 4. Many “bridge”, “tracker”, “watchdog”, and “manager” modules are just named reaction tables

Several modules sound architectural but are actually collections of event reactions:

- `Ichor.ProtocolTracker`
- `Ichor.Archon.SignalManager`
- `Ichor.Archon.TeamWatchdog`
- large parts of `Ichor.Gateway.EventBridge`
- parts of `Ichor.AgentWatchdog`

These modules often:

- subscribe to signals
- keep a small in-memory state map
- emit more signals
- write a small side effect

That is better expressed as:

- a single runtime with clearly named `handle_event/2` branches
- or a pure reducer/projection module invoked from a runtime

Multiple GenServers are not buying isolation here. They are mostly hiding control flow.

## Folder-by-folder findings

## `events`, `signals`, `observability`, `mesh`, `messages`

This area has the highest accidental complexity.

### Current shape

- `Ichor.Events.Runtime` is already the real owner of event ingestion and heartbeat/liveness
- `Ichor.EventBuffer` is just a compatibility shim
- `Ichor.Signals.Runtime` is a pubsub wrapper plus validation against `Signals.Catalog`
- `Ichor.Signals.Buffer` duplicates a recent-signal buffer
- `Ichor.Observability.*` mixes persisted records with projection-only resources
- `Ichor.Gateway.EventBridge` converts events into `DecisionLog`, updates entropy, and mirrors DAG topology
- `Ichor.Mesh.CausalDAG` and `Ichor.Mesh.DecisionLog` hold derived graph/log views
- `Ichor.Messages.Bus` also owns its own ETS message log
- `Ichor.ProtocolTracker` derives transport traces from the same underlying events

### Problems

1. There is no single answer to “where do I look for what happened?”

- event log
- signal buffer
- message ETS log
- protocol ETS log
- decision log projection
- observability projection resources

2. The code stores multiple overlapping representations of the same facts.

3. Simple read models are turned into durable-looking modules with their own folders.

4. There is a category mismatch:

- signals are transport
- events are facts
- observability models are views

The code currently gives them equal ontological weight.

### Recommendation

Collapse this into one `events` area with three responsibilities:

1. `Ichor.Events.Runtime`

- ingest raw hook events
- normalize and persist/buffer canonical events
- maintain session liveness
- publish internal notifications

2. `Ichor.Events.Projections`

- decision log projection
- topology projection
- attention projection
- transport trace projection
- recent messages projection

These do not each need their own process. Most can be pure reducers over the event stream or state owned by `Events.Runtime`.

3. `Ichor.Events.Query`

- recent events
- recent messages
- errors
- sessions
- traces
- attention

### Modules that should disappear or be absorbed

High confidence removals:

- `Ichor.EventBuffer`
- `Ichor.Signals.Buffer`
- `Ichor.ProtocolTracker`
- `Ichor.Observability.Preparations.EventBufferReader`
- `Ichor.Observability.Preparations.LoadMessages`
- `Ichor.Observability.Preparations.LoadTasks`
- `Ichor.Observability.Preparations.LoadErrors`
- `Ichor.Observability.Message`
- `Ichor.Observability.Task`
- `Ichor.Observability.Error`
- `Ichor.Observability.Session`
- `Ichor.Messages.Bus` ETS log portion

Likely absorbed:

- `Ichor.Gateway.EventBridge`
- `Ichor.Archon.SignalManager`
- `Ichor.Archon.TeamWatchdog`
- `Ichor.Mesh.DecisionLog.Helpers`

Likely retained in reduced form:

- `Ichor.Events.Runtime`
- `Ichor.Signals.Runtime`
- `Ichor.Signals.Catalog`
- `Ichor.Mesh.CausalDAG` if topology remains stateful enough to justify its own process

### Net effect

This area alone can lose 12-20 modules.

## `control`

### Current shape

`control` has both useful consolidation and leftover sprawl.

Useful parts:

- `Ichor.Control.AgentProcess` is a real runtime primitive
- `Ichor.Control.FleetSupervisor` and `Ichor.Control.TeamSupervisor` encode real lifecycle boundaries
- `Ichor.Control.Lifecycle.AgentLaunch` and `TeamLaunch` centralize launching

Sprawl:

- `Agent` and `Team` are Ash resources over runtime state
- `Control.Views.Preparations.*` reconstruct view models from runtime state and event history
- lifecycle helpers are split into many tiny modules:
  - `AgentSpec`
  - `TeamSpec`
  - `Registration`
  - `Cleanup`
  - `TmuxLauncher`
  - `TmuxScript`
- workshop/blueprint building is spread across:
  - `Blueprint`
  - `BlueprintState`
  - `Presets`
  - `TeamSpecBuilder`
  - `TmuxHelpers`
- `AgentType` is a resource-shaped vocabulary wrapper

### Problems

1. Team and agent runtime state are represented twice:

- actual GenServer/Registry state
- synthetic Ash resources for UI/tools

2. Lifecycle code is over-factored around tiny helper modules whose coupling is still extremely tight.

3. Workshop blueprint concerns leak into general fleet launch concerns.

4. There are too many types/modules for data that could be plain maps or nested structs inside one module.

### Recommendation

Collapse `control` around:

- `Ichor.Fleet.Runtime`
- `Ichor.Fleet.Agent`
- `Ichor.Fleet.Team`
- `Ichor.Fleet.Launcher`
- `Ichor.Fleet.Query`
- `Ichor.Fleet.Blueprints`

Concrete changes:

1. Replace `Ichor.Control.Agent` and `Ichor.Control.Team` Ash resources with plain service/query APIs.

2. Merge lifecycle helper modules into one launcher module plus nested structs:

- `Ichor.Fleet.Launcher.AgentSpec`
- `Ichor.Fleet.Launcher.TeamSpec`
- `Ichor.Fleet.Launcher`

3. Merge `Registration`, `Cleanup`, `TmuxLauncher`, and `TmuxScript` into the launcher layer.

4. Keep `Blueprint` as persisted configuration if the UI needs saved blueprints, but absorb:

- `BlueprintState`
- `Presets`
- `TeamSpecBuilder`
- `TmuxHelpers`

into a single `Ichor.Fleet.Blueprints` area.

### Modules that should disappear or be absorbed

High confidence removals:

- `Ichor.Control`
- `Ichor.Control.Agent`
- `Ichor.Control.Team`
- `Ichor.Control.Views.Preparations.LoadAgents`
- `Ichor.Control.Views.Preparations.LoadTeams`
- `Ichor.Control.AgentType`
- `Ichor.Control.TmuxHelpers`

Likely absorbed:

- `Ichor.Control.Lifecycle.AgentSpec`
- `Ichor.Control.Lifecycle.TeamSpec`
- `Ichor.Control.Lifecycle.Registration`
- `Ichor.Control.Lifecycle.Cleanup`
- `Ichor.Control.Lifecycle.TmuxLauncher`
- `Ichor.Control.Lifecycle.TmuxScript`
- `Ichor.Control.TeamSpecBuilder`
- `Ichor.Control.Presets`
- `Ichor.Control.BlueprintState`

Likely retained, but renamed/moved:

- `Ichor.Control.AgentProcess`
- `Ichor.Control.FleetSupervisor`
- `Ichor.Control.TeamSupervisor`
- `Ichor.Control.Lifecycle.AgentLaunch`
- `Ichor.Control.Lifecycle.TeamLaunch`
- `Ichor.Control.HostRegistry`
- `Ichor.Control.Blueprint`

### Net effect

This area can realistically lose 12-16 modules.

## `projects`

This folder has the most lines and the strongest opportunity for architectural cleanup.

### Current shape

Good consolidation already happened in persistent data:

- `Artifact` unified many former artifact resources
- `RoadmapItem` unified a hierarchy
- `Runner` unified MES/Genesis/DAG run processes

But the runtime still has several parallel control planes:

- `Runner`
- `Spawn`
- `TeamSpec`
- `Scheduler`
- `Janitor`
- `LifecycleSupervisor`
- `CompletionHandler`
- `ProjectIngestor`
- `ResearchIngestor`
- prompt modules
- graph/date/stage helpers

### Problems

1. Run orchestration is split between the runner and sidecar processes.

2. MES lifecycle is still treated as a mini-subsystem with its own supervisor tree.

3. `Spawn`, `TeamSpec`, and prompt modules are tightly coupled but separate enough to obscure execution flow.

4. The project runtime reacts to signals through extra listeners instead of owning the state transitions directly.

5. Several modules are presentation-only helpers that should not live in the domain layer.

### Recommendation

Move to one `Ichor.Projects.Runtime` area with:

- `RunManager`
- `Spawn`
- `Prompts`
- `Query`
- persistent schemas

The important simplification is: all run lifecycle transitions should live in the run manager.

That means:

- start run
- subscribe to relevant events
- detect completion/failure
- compile/load subsystem
- reset/archive jobs on failure
- clean up tmux/team/prompt artifacts

These should not be scattered across `Runner`, `CompletionHandler`, `Janitor`, and `TeamWatchdog`.

### Specific simplifications

#### 1. Fold `Scheduler`, `Janitor`, `CompletionHandler`, `ProjectIngestor`, `ResearchIngestor` into the project runtime

These modules are event/timer reaction tables, not distinct domains.

- `Scheduler` is a timer plus concurrency gate
- `Janitor` is a monitor plus cleanup branch
- `CompletionHandler` is one completion reaction
- `ProjectIngestor` is one message parser
- `ResearchIngestor` is one downstream sink

These belong in one orchestration runtime, possibly with pure helper submodules.

#### 2. Collapse `LifecycleSupervisor`

`LifecycleSupervisor` exists largely because the above modules are separate processes. Once orchestration is consolidated, this supervisor becomes much smaller or disappears into the top-level app supervisor.

#### 3. Collapse prompt generation

Current prompt code is split across:

- `ModePrompts`
- `DagPrompts`
- `TeamPrompts`
- parts of `TeamSpec`

This should become:

- `Ichor.Projects.Prompts.Mes`
- `Ichor.Projects.Prompts.Genesis`
- `Ichor.Projects.Prompts.Dag`

or even one prompt module with mode branches if preferred.

The important part is that prompt selection lives next to run/spec composition instead of being spread across builders.

#### 4. Demote utility/presentation modules

- `DateUtils` is too small to deserve a dedicated module
- `PipelineStage` is UI/query logic and should live next to queries or web presenters
- `SubsystemScaffold` is a niche generator, not core runtime
- `ResearchStore` is an adapter and should live near the research bridge, not in the core project domain

### Modules that should disappear or be absorbed

High confidence removals:

- `Ichor.Projects.Scheduler`
- `Ichor.Projects.Janitor`
- `Ichor.Projects.CompletionHandler`
- `Ichor.Projects.ProjectIngestor`
- `Ichor.Projects.ResearchIngestor`
- `Ichor.Projects.LifecycleSupervisor`
- `Ichor.Projects.DateUtils`
- `Ichor.Projects.PipelineStage`
- `Ichor.Projects.Job.Preparations.FilterAvailable`
- `Ichor.Projects.Job.Changes.SyncRunProcess`

Likely absorbed:

- `Ichor.Projects.Spawn`
- `Ichor.Projects.TeamSpec`
- `Ichor.Projects.ModePrompts`
- `Ichor.Projects.DagPrompts`
- `Ichor.Projects.TeamPrompts`
- `Ichor.Projects.SubsystemScaffold`
- `Ichor.Projects.ResearchStore`

Likely retained:

- `Ichor.Projects.Project`
- `Ichor.Projects.Node`
- `Ichor.Projects.Artifact`
- `Ichor.Projects.RoadmapItem`
- `Ichor.Projects.Run`
- `Ichor.Projects.Job`
- `Ichor.Projects.Runner` or a renamed replacement
- `Ichor.Projects.Graph`

### Net effect

This area can likely lose 12-18 modules.

## `gateway`

### Current shape

This area mixes adapters with event-derived monitoring:

- real adapters:
  - tmux
  - ssh tmux
  - webhook
  - mailbox
- runtime services:
  - cron scheduler
  - hitl relay
  - output capture
  - tmux discovery
- event-derived projections:
  - event bridge
  - entropy tracker
  - schema interceptor
  - agent registry entry

### Problems

1. Adapter code and event interpretation live side by side.

2. `EventBridge` and `EntropyTracker` are not gateways in the usual sense; they are event projections.

3. `AgentRegistry.AgentEntry` and `AnsiUtils` are helpers that do not justify nested namespaces.

### Recommendation

Split this area into:

- `Ichor.Transport.*` for tmux/webhook/mailbox/ssh adapters
- `Ichor.Fleet` or `Ichor.Events.Projections` for entropy, registry-entry parsing, and event bridge logic
- `Ichor.Runtime.Cron` or `Ichor.Transport.Cron` for scheduled delivery
- keep `HITLRelay` only if manual intervention remains a first-class runtime concern

### Modules that should disappear or move

High confidence removals or relocations:

- `Ichor.Gateway.EventBridge`
- `Ichor.Gateway.EntropyTracker`
- `Ichor.Workshop.AgentEntry`
- `Ichor.Infrastructure.Channels.AnsiUtils`

Likely retained but moved:

- `Ichor.Infrastructure.Channels.Tmux`
- `Ichor.Infrastructure.Channels.SshTmux`
- `Ichor.Infrastructure.Channels.WebhookAdapter`
- `Ichor.Infrastructure.Channels.MailboxAdapter`
- `Ichor.Gateway.CronScheduler`
- `Ichor.Infrastructure.CronJob`
- `Ichor.Gateway.HITLRelay`
- `Ichor.Gateway.OutputCapture`
- `Ichor.Gateway.WebhookRouter`
- `Ichor.Infrastructure.WebhookDelivery`

### Net effect

This area can likely lose or move 4-8 modules.

## `tools`

### Current shape

`tools` is not too fragmented compared with the rest of the code. The main issue is that Ash resources are used as tool wrappers, which leads to a lot of repetitive argument/result mapping.

### Problems

1. `RuntimeOps`, `ProjectExecution`, `AgentMemory`, and `Genesis` are very large wrapper resources.

2. Tool implementation details are mixed with formatting and Ash action boilerplate.

3. Some tools simply translate to calls into runtime modules; they do not need much resource-specific structure.

### Recommendation

Keep the tool surface, but simplify the implementation boundary:

- keep `Ichor.Tools` if AshAi requires a domain
- reduce tool implementation modules to a few plain service modules
- move result formatting into helper functions, not giant action blocks

Suggested split:

- `Ichor.Tools.Runtime`
- `Ichor.Tools.Projects`
- `Ichor.Tools.Memory`

Potentially merge `Archon.Memory` into the same memory tool module.

### Net effect

This area probably loses 2-4 modules, but the bigger win is reduced size inside the retained files.

## `memory_store`

### Current shape

`Ichor.MemoryStore` is large, but it is structurally coherent. It has a clear job and the `Storage` / `Persistence` split is understandable.

### Recommendation

Do not aggressively split this area further. If anything:

- keep `MemoryStore`
- keep `Storage`
- keep `Persistence`
- possibly extract a tiny query/helper module if needed

This is one of the few areas where the current module count is justified.

## Supervisors and application wiring

### Current shape

Supervision is currently spread across:

- `Application`
- `SystemSupervisor`
- `ObservationSupervisor`
- `Projects.LifecycleSupervisor`
- `FleetSupervisor`
- multiple dynamic supervisors

### Problems

1. Supervisors exist partly to support artificial subsystem boundaries.

2. The tree reflects current file organization more than true failure domains.

3. Some comments describe conceptual architectures that the code no longer really needs.

### Recommendation

The top-level application tree should align to runtime primitives:

- repo/pubsub/web
- fleet runtime
- event runtime
- project runtime
- memory runtime
- transport services

That likely means:

- remove `ObservationSupervisor`
- remove `Projects.LifecycleSupervisor`
- shrink `SystemSupervisor`
- keep only dynamic supervisors that correspond to actual independently restarted worker families

## Concrete module reduction plan

## Tier 1: remove obvious wrappers and shims

These are low-risk deletions after callers are redirected:

- `Ichor.EventBuffer`
- `Ichor.Observability.Preparations.EventBufferReader`
- `Ichor.Projects.DateUtils`
- `Ichor.Workshop.AgentEntry`
- `Ichor.Infrastructure.Channels.AnsiUtils`

## Tier 2: replace ephemeral Ash resources with plain query/service modules

- `Ichor.Control.Agent`
- `Ichor.Control.Team`
- `Ichor.Observability.Message`
- `Ichor.Observability.Task`
- `Ichor.Observability.Error`
- `Ichor.Observability.Session`
- all related `Preparations.*`

## Tier 3: collapse event subscribers into canonical runtimes

- `Ichor.ProtocolTracker`
- `Ichor.Signals.Buffer`
- `Ichor.Archon.SignalManager`
- `Ichor.Archon.TeamWatchdog`
- most of `Ichor.Gateway.EventBridge`
- `Ichor.Projects.CompletionHandler`
- `Ichor.Projects.ProjectIngestor`
- `Ichor.Projects.ResearchIngestor`

## Tier 4: collapse lifecycle helper clusters

- `Ichor.Control.Lifecycle.AgentSpec`
- `Ichor.Control.Lifecycle.TeamSpec`
- `Ichor.Control.Lifecycle.Registration`
- `Ichor.Control.Lifecycle.Cleanup`
- `Ichor.Control.Lifecycle.TmuxLauncher`
- `Ichor.Control.Lifecycle.TmuxScript`
- `Ichor.Control.TeamSpecBuilder`
- `Ichor.Control.Presets`
- `Ichor.Control.BlueprintState`
- `Ichor.Control.TmuxHelpers`

## Tier 5: collapse project runtime sidecars

- `Ichor.Projects.Scheduler`
- `Ichor.Projects.Janitor`
- `Ichor.Projects.LifecycleSupervisor`
- `Ichor.Projects.Spawn`
- `Ichor.Projects.TeamSpec`
- prompt modules where possible

## Proposed retained core after simplification

The system appears to need something like this:

- `Ichor.Application`
- `Ichor.Repo`
- `Ichor.Runtime.Supervisor`
- `Ichor.Events.Runtime`
- `Ichor.Events.Query`
- `Ichor.Events.Signals`
- `Ichor.Fleet.Runtime`
- `Ichor.Fleet.AgentProcess`
- `Ichor.Fleet.Launcher`
- `Ichor.Fleet.Query`
- `Ichor.Fleet.Blueprints`
- `Ichor.Projects.Runtime`
- `Ichor.Projects.RunManager`
- `Ichor.Projects.Graph`
- `Ichor.Projects.Prompts.*`
- `Ichor.MemoryStore`
- `Ichor.MemoryStore.Storage`
- `Ichor.MemoryStore.Persistence`
- transport adapters
- persisted schemas that are genuinely durable
- tool modules

That is the real shape of the codebase.

## Risks and constraints

## What should not be over-simplified

1. Persistent project schemas

The unified persistent resources in `projects` are mostly reasonable. The major win is around orchestration and projections, not deleting the actual data model.

2. Memory store

This module is big but coherent. Do not atomize it further.

3. Transport adapters

The tmux/webhook/mailbox split is justified because they are real IO boundaries.

## Main migration risk

The largest risk is changing behavior that currently emerges from many small signal subscribers. To avoid regressions:

- identify every signal currently consumed
- re-home each side effect explicitly
- make one runtime the owner of each state transition
- do not preserve legacy subscriber splits “just in case”

The refactor should reduce indirection, not merely rename files.

## Recommended implementation order

1. Establish the target architecture boundaries first.
2. Replace ephemeral Ash read models with plain query modules.
3. Collapse event-derived subscribers into `Events.Runtime` plus projection/query helpers.
4. Collapse fleet lifecycle helpers into one launcher/runtime area.
5. Collapse project orchestration around one runtime/run manager.
6. Simplify the supervision tree to match the new runtimes.
7. Shrink tool modules after the underlying services have been simplified.

## Bottom line

The code already contains evidence of the right direction:

- unified runner
- unified artifact/resource models
- unified message bus
- unified event runtime

But it stopped halfway. The old habit of creating a new module for every perspective is still dominating the design.

The simplest correct future shape is:

- one canonical event runtime
- one canonical fleet runtime
- one canonical project runtime
- one memory runtime
- a small persisted schema layer
- plain query/projection modules instead of Ash resources for ephemeral state

That will remove a large amount of code without removing any feature, because most of the removable modules are organizational veneers over the same underlying state and control flow.
