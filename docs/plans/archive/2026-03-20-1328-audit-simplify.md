# Ichor Simplification Audit

## Scope

This audit covers `lib/ichor`. The goal is structural simplification and code-footprint reduction without losing current features.

Current size at audit time:

- `lib/ichor`: 145 `.ex` files
- `lib/ichor/control`: 33 files
- `lib/ichor/projects`: 30 files
- `lib/ichor/gateway`: 20 files

## Executive Summary

The codebase already has a simpler truth hiding underneath the names:

- A small number of runtime centers do the real work.
- Many surrounding modules are wrappers, projections, or orchestration slices around those centers.
- Several namespaces are partially unified in concept but still fragmented in implementation.

The real centers are:

1. Agent runtime
2. Event ingestion and event storage
3. tmux lifecycle and delivery
4. project/run execution
5. memory persistence

Everything else is mostly one of:

- a facade over those centers
- a read model rebuilt from the same raw sources
- a tiny helper module that is not a real boundary
- an older abstraction left behind after consolidation

My conclusion: more than half of the modules in `lib/ichor` can plausibly be removed or folded into a smaller set of coherent modules without feature loss. A realistic target is reducing `lib/ichor` from 145 files to roughly 55-70 files.

## Core Architectural Finding

The code is over-partitioned by semantic naming, not by stable runtime boundaries.

That shows up repeatedly:

- one workflow split across `resource -> preparation -> query helper -> view helper -> runtime helper`
- one GenServer surrounded by tiny helper modules holding logic that used to be private functions
- multiple services reconstructing related runtime state from registry, tmux, and event buffer separately
- both Ash resources and direct runtime modules acting as “canonical entry points” for the same behavior

This creates footprint without creating useful replaceability.

## What Should Be Considered Canonical

A drastically simpler design would treat these modules or subsystems as the real backbone:

- `Ichor.Control.AgentProcess`
- one fleet runtime module for team and agent supervision
- one event pipeline module centered on `Ichor.EventBuffer`
- one tmux adapter module
- one project runtime subsystem centered on `Ichor.Projects.Runner`
- one memory subsystem centered on `Ichor.MemoryStore`

Most other modules should either disappear or become internal functions under these owners.

## Highest-Value Simplification Opportunities

### 1. Collapse duplicated agent-process helper modules back into `AgentProcess`

Files:

- `lib/ichor/control/agent_process.ex`
- `lib/ichor/control/agent_process/delivery.ex`
- `lib/ichor/control/agent_process/lifecycle.ex`
- `lib/ichor/control/agent_process/mailbox.ex`
- `lib/ichor/control/agent_process/registry.ex`

Findings:

- `Ichor.Control.AgentProcess` already contains private implementations of delivery, lifecycle, mailbox, and registry shaping.
- The split helper modules exist in parallel.
- `rg` only found references to the helper modules in their own files; they are effectively dead or abandoned extractions.
- `AgentProcess.Registry` duplicates functions already present in `AgentProcess`.
- `Delivery`, `Lifecycle`, and `Mailbox` repeat logic that is still implemented directly in `AgentProcess`.

Impact:

- Remove 4 files immediately.
- Keep one file: `AgentProcess`.
- If helper extraction is still desired, use private functions in the same file or one internal module, not four parallel public modules.

### 2. Collapse duplicated watchdog helper modules or delete them

Files:

- `lib/ichor/agent_watchdog.ex`
- `lib/ichor/agent_watchdog/event_state.ex`
- `lib/ichor/agent_watchdog/pane_parsing.ex`
- `lib/ichor/agent_watchdog/nudge_policy.ex`

Findings:

- `Ichor.AgentWatchdog` already embeds logic matching the helper modules.
- `EventState` is not referenced by the main watchdog.
- `PaneParser` and `NudgePolicy` duplicate the private functions in `agent_watchdog.ex`.
- The code comments claim consolidation already happened, but the old split remains.

Impact:

- Remove 3 files.
- Keep one watchdog module, or if needed split into two internal files only: `AgentWatchdog` and a truly shared parser module.

### 3. Replace the current control read-model sprawl with one runtime snapshot layer

Files:

- `lib/ichor/control/agent.ex`
- `lib/ichor/control/team.ex`
- `lib/ichor/control/views/preparations/load_agents.ex`
- `lib/ichor/control/views/preparations/load_teams.ex`
- `lib/ichor/control/runtime_query.ex`
- `lib/ichor/control/runtime_view.ex`
- `lib/ichor/control/lookup.ex`
- `lib/ichor/control/analysis/agent_health.ex`
- `lib/ichor/control/analysis/queries.ex`

Findings:

- Agents and teams are reconstructed from a mix of:
  - registry metadata
  - event buffer
  - tmux sessions
  - task files
- This happens in multiple places with slightly different shapes.
- `LoadTeams` is doing discovery, enrichment, health derivation, dead-team classification, and resource conversion.
- `RuntimeView`, `RuntimeQuery`, and `Analysis.Queries` are adjacent projection layers over the same runtime sources.
- `Lookup` is a thin wrapper over `Agent.all!()`.

Recommendation:

- Create one explicit runtime snapshot module, for example `Ichor.Control.Runtime`.
- It should produce one canonical in-memory shape:
  - agents
  - teams
  - sessions
  - tasks
  - health
- Make Ash resources, LiveViews, and tools read from that snapshot instead of each building a partial projection.

Likely removals:

- `control/views/preparations/load_agents.ex`
- `control/views/preparations/load_teams.ex`
- `control/runtime_query.ex`
- `control/runtime_view.ex`
- `control/lookup.ex`
- `control/analysis/queries.ex`

`control/analysis/agent_health.ex` can stay only if reused cleanly, otherwise fold into the runtime snapshot.

### 4. Remove dual ownership of agent existence between `Events.Runtime` and `TmuxDiscovery`

Files:

- `lib/ichor/events/runtime.ex`
- `lib/ichor/gateway/tmux_discovery.ex`

Findings:

- `Events.Runtime` resolves or creates agents from incoming events.
- `TmuxDiscovery` also ensures a BEAM process exists for every tmux session and reaps dead agents.
- Both modules are trying to establish the canonical agent inventory.
- This is the kind of overlap that causes “ghost” lifecycle logic and hard-to-reason-about recovery.

Recommendation:

- Pick one owner for agent creation/reaping.
- Preferred:
  - `Events.Runtime` owns event-to-agent association.
  - a much smaller tmux poller only enriches tmux metadata and discovers sessions when there is no event stream yet.
- Or invert it:
  - fleet runtime owns inventory
  - event runtime only annotates.

Either way, eliminate split authority.

### 5. Merge `HeartbeatManager` into `AgentWatchdog` or remove heartbeats entirely

Files:

- `lib/ichor/gateway/heartbeat_manager.ex`
- `lib/ichor/agent_watchdog.ex`
- `lib/ichor/events/runtime.ex`

Findings:

- `AgentWatchdog` already emits heartbeat signals and performs stale/crash/escalation checks.
- `HeartbeatManager` maintains a second liveness store and emits evictions.
- `Events.Runtime.record_heartbeat/2` delegates into `HeartbeatManager`.
- This is a separate liveness subsystem beside watchdog-based liveness and tmux liveness.

Recommendation:

- One liveness source only.
- If heartbeats are still needed for external sessions, store heartbeat timestamps in the same watchdog/fleet runtime state.
- Delete `HeartbeatManager` as a standalone GenServer.

### 6. Shrink the observation stack to one event projection pipeline

Files:

- `lib/ichor/gateway/event_bridge.ex`
- `lib/ichor/gateway/entropy_tracker.ex`
- `lib/ichor/gateway/topology_builder.ex`
- `lib/ichor/mesh/causal_dag.ex`
- `lib/ichor/gateway/schema_interceptor.ex`
- `lib/ichor/protocol_tracker.ex`
- `lib/ichor/observation_supervisor.ex`

Findings:

- The observation path is spread across many runtime processes:
  - `EventBridge`
  - `EntropyTracker`
  - `TopologyBuilder`
  - `CausalDAG`
  - `ProtocolTracker`
- `SchemaInterceptor` also does entropy enrichment synchronously.
- `TopologyBuilder` is mostly a PubSub subscription adapter over `CausalDAG`.
- `ProtocolTracker` is another event-derived view with separate ETS state.

Recommendation:

- Build one observation pipeline around event ingestion plus projection tables.
- `EventBridge` can become the owner that updates:
  - decision log projection
  - entropy counters
  - topology projection
  - protocol summary
- `TopologyBuilder` can likely disappear into a pure function plus direct signal emission.
- `EntropyTracker` does not need to be a GenServer if its state can live in ETS owned by the event pipeline or directly in `EventBuffer`.
- `ProtocolTracker` looks optional and dashboard-oriented; make it a derived query or fold it into the same observation store.

Likely end state:

- keep `EventBuffer`
- keep one `Observations` runtime process
- keep `CausalDAG` only if the DAG semantics are truly essential
- remove `TopologyBuilder`
- remove standalone `EntropyTracker`
- remove standalone `ProtocolTracker`
- likely remove `ObservationSupervisor` by folding those children into one runtime process

### 7. Simplify system supervision

Files:

- `lib/ichor/application.ex`
- `lib/ichor/system_supervisor.ex`
- `lib/ichor/observation_supervisor.ex`
- `lib/ichor/projects/lifecycle_supervisor.ex`

Findings:

- Supervision is split into category supervisors even where real restart-domain boundaries are weak.
- `SystemSupervisor` groups many unrelated processes.
- `ObservationSupervisor` exists mostly because the observation stack is fragmented.
- `Projects.LifecycleSupervisor` still reflects an older subsystem naming style.

Recommendation:

- Keep supervision aligned to real failure domains only:
  - fleet
  - events/observations
  - projects/runs
  - memory
- If observation and project subsystems are flattened, their extra supervisors can disappear.

### 8. Finish the project subsystem consolidation around `Runner`

Files:

- `lib/ichor/projects/runner.ex`
- `lib/ichor/projects/scheduler.ex`
- `lib/ichor/projects/janitor.ex`
- `lib/ichor/projects/runtime.ex`
- many `lib/ichor/projects/*` Ash resources and helper modules

Findings:

- `Runner` is already a strong simplification: it replaced several prior run implementations with one data-driven process.
- But the rest of the project subsystem still carries old layering:
  - scheduler
  - janitor
  - runtime poller
  - multiple resources
  - multiple prompt/build/load helpers
- `Projects.Runtime` is large because it absorbed prior modules, which is directionally correct.
- `Scheduler` and `Janitor` still look like legacy subsystem-specific coordination layers.

Recommendation:

- Treat `Runner` and a single `Projects.Runtime` coordinator as the only real runtime modules.
- Fold `Scheduler` and `Janitor` responsibilities into `Projects.Runtime` unless they need isolated restart policy.
- Audit every `projects/*prompts*`, `research_*`, and `subsystem_*` module:
  - keep pure content modules only if they are large and isolated by responsibility
  - otherwise fold into the caller

This area probably has the second-largest removable footprint after `control`.

### 9. Reduce Ash resource count for runtime-only concepts

Files:

- `lib/ichor/control/agent.ex`
- `lib/ichor/control/team.ex`
- `lib/ichor/control/blueprint.ex`
- `lib/ichor/control/agent_type.ex`
- `lib/ichor/gateway/cron_job.ex`
- `lib/ichor/gateway/webhook_delivery.ex`
- multiple `projects/*.ex` resources
- `lib/ichor/signals/event.ex`

Findings:

- Ash is being used for two distinct things:
  - persisted business data
  - runtime facades over live state
- The first category makes sense.
- The second category creates action, preparation, and domain overhead for data that is already in memory.
- `Signals.Event` is especially thin and feels like tooling exposure rather than a real domain resource.

Recommendation:

- Keep Ash for durable data models:
  - jobs
  - runs
  - projects
  - artifacts
  - roadmap items
  - maybe webhook deliveries / cron jobs
- Remove or demote Ash resources that are just runtime facades:
  - `Control.Agent`
  - `Control.Team`
  - `Signals.Event`
- Expose those as plain modules or tool adapters over the new runtime snapshot.

### 10. Flatten `Archon.Chat` into one conversation module

Files:

- `lib/ichor/archon/chat.ex`
- `lib/ichor/archon/chat/chain_builder.ex`
- `lib/ichor/archon/chat/turn_runner.ex`
- `lib/ichor/archon/chat/context_builder.ex`
- `lib/ichor/archon/chat/command_registry.ex`

Findings:

- The chat flow is straightforward:
  - parse slash command or
  - build chain, add context/history, run turn
- It is split into five files, but the boundaries are weak.
- `CommandRegistry` is effectively a big command dispatch table.
- `ChainBuilder` and `TurnRunner` are only meaningful if chain composition is reused elsewhere, which currently does not appear to be the case.

Recommendation:

- Collapse into:
  - `Archon.Chat`
  - optionally `Archon.Chat.Commands`
- Remove `ChainBuilder`, `TurnRunner`, and `ContextBuilder` as standalone public modules unless tests prove they need isolation.

### 11. Collapse `MemoryStore` back into one subsystem module unless storage is reused externally

Files:

- `lib/ichor/memory_store.ex`
- `lib/ichor/memory_store/storage.ex`
- `lib/ichor/memory_store/persistence.ex`

Findings:

- The split is understandable, but it is still one tightly coupled subsystem built around ETS plus disk flush.
- `Storage` and `Persistence` are not general-purpose libraries.
- `MemoryStore` owns lifecycle, dirty tracking, ETS tables, and persistence scheduling anyway.

Recommendation:

- Collapse to one file plus maybe one private persistence helper if the file becomes too large.
- Do not keep multiple public modules unless external callers truly use them as boundaries.

This is a moderate simplification opportunity, not as urgent as control or observation.

### 12. Task storage has unnecessary layering and duplicate storage models

Files:

- `lib/ichor/tasks/board.ex`
- `lib/ichor/tasks/team_store.ex`
- `lib/ichor/tasks/jsonl_store.ex`

Findings:

- `Board` is a very thin signal-emitting wrapper over `TeamStore`.
- `TeamStore` uses one per-task JSON file storage.
- `JsonlStore` mutates a different task storage format using shell tools.
- This is two task persistence models with slightly different APIs.

Recommendation:

- Choose one task storage model.
- If both must exist, centralize them behind one module with two backends, not parallel top-level modules.
- `Board` can be absorbed into the chosen task store or runtime service.

### 13. Some modules appear to exist only as naming artifacts

Strong candidates:

- `lib/ichor/control/lookup.ex`
- `lib/ichor/control/runtime_view.ex`
- `lib/ichor/control/runtime_query.ex`
- `lib/ichor/control/analysis/queries.ex`
- `lib/ichor/signals/event.ex`
- `lib/ichor/events/event.ex`
- `lib/ichor/gateway/channel.ex` if channel polymorphism is reduced

These are not all bad modules, but several are “one extra level of name” rather than a durable seam.

## Concrete Delete-or-Merge Candidates

High-confidence removals or folds:

- `lib/ichor/control/agent_process/delivery.ex`
- `lib/ichor/control/agent_process/lifecycle.ex`
- `lib/ichor/control/agent_process/mailbox.ex`
- `lib/ichor/control/agent_process/registry.ex`
- `lib/ichor/agent_watchdog/event_state.ex`
- `lib/ichor/agent_watchdog/pane_parsing.ex`
- `lib/ichor/agent_watchdog/nudge_policy.ex`
- `lib/ichor/control/lookup.ex`
- `lib/ichor/control/runtime_query.ex`
- `lib/ichor/control/runtime_view.ex`
- `lib/ichor/control/analysis/queries.ex`
- `lib/ichor/gateway/topology_builder.ex`
- `lib/ichor/gateway/heartbeat_manager.ex`
- `lib/ichor/protocol_tracker.ex`
- `lib/ichor/tasks/board.ex`
- `lib/ichor/signals/event.ex`

Strong merge candidates:

- `lib/ichor/events/runtime.ex` + parts of `lib/ichor/gateway/tmux_discovery.ex`
- `lib/ichor/gateway/event_bridge.ex` + `lib/ichor/gateway/entropy_tracker.ex` + `lib/ichor/gateway/topology_builder.ex`
- `lib/ichor/archon/chat/*.ex` into `lib/ichor/archon/chat.ex`
- `lib/ichor/memory_store*.ex` into one subsystem owner
- `lib/ichor/projects/scheduler.ex` + `lib/ichor/projects/janitor.ex` into `lib/ichor/projects/runtime.ex`

## Proposed Target Shape

### Fleet

- `Ichor.Control.Runtime`
- `Ichor.Control.AgentProcess`
- `Ichor.Control.FleetSupervisor`
- `Ichor.Control.TeamSupervisor`
- one tmux lifecycle helper module

### Events / Observations

- `Ichor.Events.Runtime`
- `Ichor.EventBuffer`
- one `Ichor.Observations` runtime process
- optional `Ichor.Mesh.CausalDAG` if truly needed

### Projects

- `Ichor.Projects.Runtime`
- `Ichor.Projects.Runner`
- persisted Ash resources only where data must be queryable and durable

### Memory

- `Ichor.MemoryStore`

### Tools / Archon

- `Ichor.Tools.RuntimeOps`
- `Ichor.Tools.ProjectExecution`
- `Ichor.Tools.Genesis`
- `Ichor.Archon.Chat`
- `Ichor.Archon.SignalManager`

This structure keeps the product surface while dramatically reducing internal plumbing.

## Why So Many Modules Can Be Removed

Because the current code often uses modules as labels for subtopics, not as units of replacement or isolation.

Examples:

- `AgentProcess` and `AgentProcess.*` are not separate deployable concerns.
- `LoadTeams`, `RuntimeView`, `RuntimeQuery`, and `Analysis.Queries` are all readers over the same live state.
- `EventBridge`, `EntropyTracker`, `TopologyBuilder`, and `ProtocolTracker` are all event-derived projections.
- `Archon.Chat.*` is one linear request flow.

That is why the total file count is inflated beyond the true number of moving parts.

## Refactor Order

### Phase 1: Remove dead parallel extractions

- fold `control/agent_process/*` into `AgentProcess`
- fold `agent_watchdog/*` into `AgentWatchdog`
- delete thin wrappers with no real boundary

This is the safest, highest-confidence reduction.

### Phase 2: Unify runtime read models

- introduce one fleet runtime snapshot
- move dashboards, tools, and resources to it
- remove duplicate projections

This is where most control-layer simplification happens.

### Phase 3: Unify event ownership

- choose one owner for agent discovery and liveness
- collapse observation sidecars into one event projection pipeline

This removes a lot of GenServer overhead and cross-module coupling.

### Phase 4: Finish project subsystem consolidation

- fold scheduler/janitor into project runtime where practical
- reduce helper and prompt scattering

### Phase 5: Demote runtime Ash facades

- convert runtime-only resources to plain modules or tool-facing adapters

## Risks

The main risk is not feature loss. It is accidental behavioral drift in implicit side effects.

Areas that need careful preservation during refactor:

- signal emission points
- tmux cleanup semantics
- team/agent registry metadata shape
- dashboard expectations around current field names
- Ash action interfaces used by tools and LiveViews

These are manageable if the simplification is done by preserving public surfaces while replacing the internal source of truth.

## Final Assessment

`lib/ichor` is not fundamentally too complex because the product is too complex. It is too complex because the same runtime concerns are represented multiple times under different semantic names.

The good news is that the design is already trying to converge:

- `AgentWatchdog` already claims to have replaced older monitors.
- `Runner` already claims to have unified prior run processes.
- `Messages.Bus` already claims to be the single delivery authority.
- `Projects.Runtime` already absorbed multiple older modules.

The next step is to finish that convergence instead of keeping both the new center and the old slices.

If this refactor is done rigorously, the codebase should become:

- smaller
- easier to reason about
- easier to supervise
- easier to test
- more explicit about true ownership boundaries

without losing any visible capability.
