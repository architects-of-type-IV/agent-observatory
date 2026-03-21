# ICHOR IV Architecture Blueprint

**Date**: 2026-03-21
**Status**: Reviewed -- codex sparring complete (8.5/10)

Related: [Glossary](GLOSSARY.md) | [Diagrams](../diagrams/architecture.md) | [Database Schema](../diagrams/database-schema.md) | [Codex Sparring](../reviews/2026-03-21-codex-sparring.md)

---

## Part 1: Architectural Decisions

### AD-1: Ash as Business Boundary

**Decision**: Ash domains are the exclusive public API for all durable business state. Callers invoke domain-owned actions; they do not call resource modules directly or construct changesets outside a resource's own action blocks.

**Context**: Ash actions are the composable unit of work that Discovery will expose for dynamic workflow composition. An action with a description, typed arguments, typed return, and a policy is discoverable, auditable, and pipeable.

**Rationale**: 90% declared, 10% imperative. Ash makes that achievable only if the boundary is respected. Raw `Ash.create/1` calls from business logic are not discoverable. `define` in the code interface is.

**Consequences**: Enables Discovery. Policies become enforceable. Actions become directly composable in UI-built workflows. Constraint: no direct resource module calls from outside the owning domain.

### AD-2: Signals (Ichor) Are the Nervous System

**Decision**: Signals carry facts across bounded-context lines. Direct function calls remain correct within a cohesive subsystem. Signals are not a universal replacement for calls.

**Context**: Ichor = the divine fluid. Signals are the lifeblood. But lifeblood does not mean every message. A signal says "this fact occurred." A subscriber decides what to do. This is the right model when the emitter should not know who reacts.

**Rationale**: Use signals when a fact crosses a domain line. Call directly when two modules belong to the same subsystem. Overusing signals creates event soup and weakens traceability.

**Consequences**: Signal topology becomes the architecture diagram. Direct calls within a subsystem remain traceable. Constraint: never emit a signal to coordinate something in the same subsystem.

### AD-3: spawn/1 Is Generic

**Decision**: `spawn(team_name)` is a generic compile-and-launch operation. The team name resolves to a Workshop design. What the team does is determined by its prompts, not by a mode parameter.

**Context**: Current `TeamSpec.build(:mes | :pipeline | :planning)` puts caller knowledge inside the Workshop compiler. Three spawn implementations duplicate logic and diverge.

**Rationale**: The mistake is not having specialized orchestrators (pipeline needs DAG validation). The mistake is letting the compiler own their knowledge. `TeamSpec.compile(state, opts)` with injected `prompt_module` preserves testable prompt code while eliminating mode dispatch inside Workshop.

**Consequences**: Adding a new team type requires no TeamSpec changes. Constraint: each team record must carry a `prompt_module` binding.

### AD-4: Three Strata

**Decision**: (1) Pure model/query/compilation code -- no side effects. (2) Application orchestrators -- coordinate between model and runtime. (3) Runtime adapters -- tmux, filesystem, HTTP, bash at the outer edge.

**Context**: Filesystem paths, System.cmd, tmux control, and JSON mutation are spread through business logic. The effect boundary is too porous.

**Rationale**: Pure code is testable without process infrastructure. Orchestrators are testable by injecting adapter fakes. Adapters are integration-tested at their boundary. This is the Elixir-native "functional core, imperative shell."

**Consequences**: PipelineMonitor becomes pure query module + Oban cron. TeamSpec.compile has no I/O. Adapter modules are the only places that touch the filesystem or shell.

### AD-5: Authority Model

**Decision**: Four authorities. (1) Ash resources for durable business state. (2) Registry + supervised processes for live runtime state. (3) External files for interoperability. (4) Signals carry facts, not ownership.

**Context**: Events, tmux state, JSONL files, registry entries, and Ash records all participate in truth without making authority explicit.

**Rationale**: When authority is ambiguous, every read requires reconciliation. Explicit authority means: canonical task status = PipelineTask (Ash). Agent alive? = Registry. External project tasks = tasks.jsonl (interop). No reconciliation needed.

**Consequences**: EventStream no longer auto-creates fleet entities. PipelineMonitor file reads become interop adapter. Ash is never bypassed for durable state writes.

### AD-6: Prompt Strategy Injection

**Decision**: `TeamSpec.compile/2` accepts a `prompt_module` option. Callers provide their own module implementing the prompt-building contract. The compiler has zero knowledge of MES, pipeline, or planning.

**Context**: TeamSpec.build/N hardcodes PlanningPrompts (Factory module) inside Workshop. CRITICAL RULES block copied verbatim in 11+ functions.

**Rationale**: Prompt logic changes when the agent protocol changes. Compilation logic changes when the canvas model changes. These are separate axes of change. Option A (prompt_module per team) keeps prompts as versioned, testable Elixir code.

**Consequences**: Shared protocol blocks extracted into Workshop.PromptProtocol. Adding a new team type = one new prompt module + binding on Team record. No Factory imports in Workshop.

### AD-7: Typed Value Objects Over Stringly-Typed Identifiers

**Decision**: `RunRef`, `AgentId`, and `SessionRef` are explicit structs with `parse/1` and `format/1`. All pattern-matching on run kinds and session formats happens through these types.

**Context**: `runner.ex` has five functions each with three clauses on `:mes | :pipeline | :planning`. Two field names (`session_id` vs `agent_id`) for the same concept. String parsing by hand in multiple modules.

**Rationale**: A value object consolidates parsing to one place. `%RunRef{kind: :pipeline}` in function heads is correct Elixir dispatch. `"pipeline-" <> _` in multiple modules is fragile string archaeology.

**Consequences**: Runner mode dispatch collapses from 5x3 clause trees to RunRef-dispatched heads. New run kinds = one constructor, not six file edits.

### AD-8: Reliability Boundary -- Ash -> Oban -> PubSub (from codex sparring)

**Decision**: Three reliability layers. (1) Ash resources are durable truth. (2) Oban jobs are durable execution -- mandatory reactions insert Oban jobs directly from Ash notifiers/action bodies, not via PubSub subscribers. (3) PubSub signals are observational fanout only -- UI updates, logs, topology refreshes. Loss is acceptable.

**Context**: The original design routed mandatory work (cleanup, task reassignment, escalation) through PubSub -> subscriber -> Oban.insert. Codex identified the volatile hop: if the subscriber is down when the signal fires, the Oban job never gets enqueued. That's not delayed execution -- it's absent execution.

**Rationale**: If something must happen, persist intent durably first. If something is merely interesting, publish a signal. Ash notifiers fire after commit -- inserting an Oban job there is effectively an atomic durable enqueue. A periodic reconciler Oban cron checks for orphaned intents (e.g., Pipeline stuck in :active with no Runner).

**Consequences**: PubSub is demoted to observation-only. Cleanup/reassignment/webhook retry insert Oban jobs directly. The reconciler catches crash-window failures. Every Oban worker must be idempotent. Constraint: no mandatory work flows through PubSub alone.

---

## Part 2: Tech Choices

**Ash Framework** (not raw Ecto): Ash provides the composable action model Discovery requires. Actions are first-class named operations with typed arguments, descriptions, policies, and return shapes. The specific capabilities: code interfaces, generic actions, notifiers, and policies. 90% of the business layer declared rather than imperative.

**AshSqlite**: SQLite for a single-node developer tool. No Postgres infrastructure. Known constraints: no aggregates at data layer (compute in Elixir after read), no ALTER COLUMN (enforce at Ash level, remove column-modify from generated migrations).

**Oban**: Replaces three GenServer timer patterns (MesScheduler, CronScheduler, PipelineMonitor health). Key capability: reliable retry with backoff. Queue-level pause/resume replaces file-flag mechanism.

**tmux**: Claude Code agents require a persistent PTY with visible output, text input, and window addressing. tmux provides all three natively. `tmux attach` is zero-cost debugging.

**ETS for runtime projections**: O(1) concurrent reads without GenServer serialization. Multiple LiveViews read the event buffer simultaneously. GenServer handles writes + subscriptions only.

**PubSub for signals**: Subscriber set is dynamic and unknown to the emitter at compile time. Any process can subscribe to any topic without registration. Fire-and-forget with no backpressure -- correct for observational facts. Directed agent messages use Bus (direct delivery) because the sender has a specific target.

---

## Part 3: Ownership Rules

### Decision Rule: When to Use Each Construct

**Ash Resource** when: data must be persisted, queried across requests, exposed via MCP tools, or operated on by multiple callers needing a typed, discoverable interface. Resources own durable facts. Must have policies.

**Plain Elixir module** when: pure transformation, in-memory query, or adapter to an external system with no business identity. `CanvasState`, `TeamSpec`, `PipelineGraph`, `Board` are correct examples.

**Long-lived OTP process** when: genuinely owned mutable runtime state that cannot be reconstructed on demand and that multiple callers need to observe concurrently. `EventStream` (ETS buffer), `AgentProcess` (IS the agent), `FleetSupervisor` (supervision topology), `HITLRelay` (pause state). NOT for caching recomputable state (PipelineMonitor violates this).

**Oban worker** when: work must survive a crash and be retried, is expensive enough to not block a caller, or needs cron-style scheduling. Cleanup, webhook delivery, health checks, periodic scheduling.

### Domain Ownership

| Domain | Owns | Does NOT Own | Authority | Communication |
|--------|------|-------------|-----------|---------------|
| **Workshop** | Team designs, canvas state, team compilation, agent types, spawn coordination | Prompt content for specific modes (binding yes, content no). AgentWatchdog. Spawn mode dispatch | SQLite (Ash) for designs. Registry for live fleet | Emits signals. Calls Infrastructure.TeamLaunch. Must NOT call Factory |
| **Factory** | Project lifecycle, pipeline/task tracking, run orchestration, external file interop | Team compilation (delegates to Workshop). Board mutation on agent crash (should subscribe to signal) | Ash for runs/tasks. tasks.jsonl for interop | Emits signals. Calls Workshop.TeamSpec.compile. Exposes MCP tools |
| **Archon** | Archon's management tool surface (Manager, Memory). Run cleanup orchestration | Domain-specific cleanup logic (should emit signals, let domains react). MemoriesClient (should be Infrastructure) | Archon.Memory for agent memory | Subscribes to fleet/pipeline/planning signals. Emits cleanup signals |
| **SignalBus** | Signal action surface, message delivery (Bus), event store | Fleet mutations (EventStream coupling). AgentWatchdog (fleet concern, not signal concern) | Message log (ETS). Event buffer (ETS, ephemeral) | IS the communication mechanism. Does not call into other domains |
| **Infrastructure** | Runtime host: supervisors, registry, tmux, launch execution, adapters | Business logic. Should not be an Ash Domain unless justified by MCP tool surface | Registry for live process state. tmux for agent backend | Called by Workshop and Factory. Emits agent lifecycle signals |
| **Mesh** | Causal DAG, event bridge, decision log. Observability topology | Nothing from other domains. Clean boundary | DAG for event ordering (ephemeral) | Subscribes to event stream. Does not emit to other domains |

---

## Part 4: Gap Analysis

| # | Gap | Current | Target | Priority |
|---|-----|---------|--------|----------|
| 1 | Effect boundary porosity | `~/.claude/`, `System.cmd`, `File.ls` scattered in business logic | Filesystem adapters per boundary. `System.cmd` only in Infrastructure.Tmux | High |
| 2 | Authorization absent | No `policies do` blocks. No actor threading. Actions callable without identity | Every resource has policies. Actor threaded through all call sites | Critical |
| 3 | Typed identifiers missing | Bare strings for run_id, session_id, team_name. Parsed by hand in 5+ modules | RunRef, AgentId, SessionRef structs with parse/format | High |
| 4 | TeamSpec carries caller knowledge | Imports Factory.PlanningPrompts. Three build/N heads with mode-specific code | `compile(state, opts)` with injected prompt_module. No Factory imports | High |
| 5 | EventStream auto-registration coupling | Event ingestion creates/terminates fleet entities directly | Emit :session_discovered. Infrastructure subscriber creates AgentProcess | High |
| 6 | AgentWatchdog cross-domain calls | Calls Factory.Board + Infrastructure.HITLRelay directly | Emit signals. Factory/Infrastructure subscribers react | Medium |
| 7 | PipelineMonitor singleton cache | 623-line GenServer serializing all reads, running bash in GenServer.call | Pure query module + Oban cron workers | Medium |
| 8 | Supervision topology flat | 14 children in one one_for_one bucket mixing concerns | Sub-supervisors grouped by failure domain | Medium |
| 9 | Ash domains are catalogs | Resources callable directly, bypassing domain code interface | Code interfaces enforced. Policies evaluated at domain boundary | High |
| 10 | Two parallel spawn paths | Workshop.Spawn + Factory.Spawn duplicate compilation, diverge on naming/lifecycle | One compile path via TeamSpec.compile. Factory does pre-spawn work, then calls spawn | Medium |

---

## Part 5: Actionable Tasks (25 tasks, 5 waves)

### Wave 1: Foundation (7 tasks, all small, fully parallel)

| ID | What | Why | Files |
|----|------|-----|-------|
| W1-1 | Extract Operator.Inbox module | A3: three modules write inbox JSON with different schemas | New operator/inbox.ex, agent_watchdog.ex, team_watchdog.ex |
| W1-2 | Remove AgentWatchdog duplicate functions | P2: incomplete extraction artifact | agent_watchdog.ex |
| W1-3 | Fix EventBridge raw PubSub calls | 2.3: bypasses Ichor.Signals facade | event_bridge.ex |
| W1-4 | Move EventBridge to Mesh namespace | W2: already supervised by Mesh.Supervisor | event_bridge.ex -> mesh/ |
| W1-5 | Move MemoriesClient to Infrastructure | W5: three domains consume it | archon/memories_client.ex -> infrastructure/ |
| W1-6 | Extract shared prompt protocol | S1: CRITICAL RULES duplicated in 11+ functions | New workshop/prompt_protocol.ex |
| W1-7 | Add Ash action descriptions | P3: Discovery requires descriptions | team.ex, agent.ex, floor.ex, operations.ex |

### Wave 2: Signal Decoupling (3 tasks, 1 small + 2 medium, parallel)

| ID | What | Why | Blocked by |
|----|------|-----|-----------|
| W2-1 | Task reassignment -> Factory subscriber on :agent_crashed | 2.2: Signals calls Factory directly | none |
| W2-2 | Escalation -> Infrastructure subscriber | 2.1: Signals calls HITLRelay directly | none |
| W2-3 | EventStream fleet mutation -> :session_discovered signal | X1: event store mutates fleet | none |

### Wave 3: Spawn Convergence (6 tasks, 1 large + 3 medium + 2 small)

| ID | What | Blocked by |
|----|------|-----------|
| W3-1 | Add prompt_module field to Team/Preset | none |
| W3-2 | Refactor TeamSpec.build/N -> compile/2 | W3-1 |
| W3-3 | Converge Workshop.Spawn onto TeamSpec.compile | W3-2 |
| W3-4 | Move PlanningPrompts to Workshop | W3-2 |
| W3-5 | Consolidate Agent's 4 spawn actions to 2 | none (parallel) |
| W3-6 | RunRef value object replaces mode dispatch | none (parallel) |

### Wave 4: Process Elimination (4 tasks, 2 large + 2 medium)

| ID | What | Blocked by |
|----|------|-----------|
| W4-1 | MesScheduler -> Oban cron worker | W3-2 |
| W4-2 | CronScheduler -> Oban cron config | none |
| W4-3 | Eliminate PipelineMonitor GenServer | W4-1, W3-6 |
| W4-4 | TeamWatchdog -> signal-to-job dispatcher | W1-1, W2-x |

### Wave 5: Ash Strengthening (5 tasks, all medium)

| ID | What | Blocked by |
|----|------|-----------|
| W5-1 | Replace opaque :map returns with typed outputs | W3-5, W1-7 |
| W5-2 | Add Ash policies to Workshop + Factory | W1-7 |
| W5-3 | Implement Ichor.Discovery module | W1-7, W5-1, W5-2 |
| W5-4 | AgentId value object | W3-6 |
| W5-5 | Move Infrastructure Ash resources to correct domains | W4-2, W2-2 |

### Dependency Graph

```
Wave 1: W1-1 through W1-7 (all parallel)
Wave 2: W2-1 through W2-3 (all parallel, no Wave 1 deps)
Wave 3: W3-1,W3-5,W3-6 parallel -> W3-2 -> W3-3,W3-4
Wave 4: W4-2 anytime | W4-1 after W3-2 | W4-3 after W4-1+W3-6 | W4-4 after W1-1+W2-x
Wave 5: W5-1,W5-2,W5-4 parallel | W5-5 after W4-2+W2-2 | W5-3 last (needs W1-7+W5-1+W5-2)
```

---

## Part 6: Vertical Slice Summary

| UC | Slice | Clean? | Key gap |
|----|-------|--------|---------|
| 1. Design a Team | Workshop only | Yes | Action descriptions missing (W1-7) |
| 2. Launch a Team | Workshop.Spawn -> TeamLaunch | Partially | Parallel spec builder, no prompt_module (W3-1,3) |
| 3. Start Planning | Factory -> TeamSpec -> TeamLaunch -> Runner | No | TeamSpec imports Factory (W3-2) |
| 4. Build a Project | Factory -> Loader/Validator/Groups -> TeamSpec -> Runner | No | Same as UC3 + PipelineMonitor coupling (W4-3) |
| 5. Monitor Fleet | Events -> EventStream -> Signals -> Dashboard | No | Fleet mutation in event store (W2-3) |
| 6. Communicate | Dashboard -> Bus -> AgentProcess/Tmux | Mostly | Stringly-typed targets (W5-4) |
| 7. Manage Tasks | Dashboard -> PipelineMonitor + PipelineTask | No | Singleton cache GenServer (W4-3) |
| 8. Archon Governs | Signals -> TeamWatchdog -> cross-domain calls | No | Direct calls, no Oban retry (W4-4) |
| 9. Discovery (planned) | Ash introspection -> action catalog -> workflow UI | N/A | Requires W1-7, W5-1, W5-2, W5-3 |
