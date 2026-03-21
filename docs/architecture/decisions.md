# Architectural Decisions
Related: [Index](INDEX.md) | [Codex Sparring](../reviews/2026-03-21-codex-sparring.md) | [Vertical Slices](../plans/2026-03-21-vertical-slices.md)

**Codex Rating: 8.5/10** -- See [codex sparring transcript](../reviews/2026-03-21-codex-sparring.md) for full session. AD-8 emerged directly from that session.

---

## AD-1: Ash as Business Boundary

**Decision**: Ash domains are the exclusive public API for all durable business state. Callers invoke domain-owned actions; they do not call resource modules directly or construct changesets outside a resource's own action blocks.

**Context**: Ash actions are the composable unit of work that Discovery will expose for dynamic workflow composition. An action with a description, typed arguments, typed return, and a policy is discoverable, auditable, and pipeable.

**Rationale**: 90% declared, 10% imperative. Ash makes that achievable only if the boundary is respected. Raw `Ash.create/1` calls from business logic are not discoverable. `define` in the code interface is.

**Consequences**: Enables Discovery. Policies become enforceable. Actions become directly composable in UI-built workflows. Constraint: no direct resource module calls from outside the owning domain.

---

## AD-2: Signals Are the Nervous System

**Decision**: Signals carry facts across bounded-context lines. Direct function calls remain correct within a cohesive subsystem. Signals are not a universal replacement for calls.

**Context**: Ichor = the divine fluid. Signals are the lifeblood. But lifeblood does not mean every message. A signal says "this fact occurred." A subscriber decides what to do. This is the right model when the emitter should not know who reacts.

**Rationale**: Use signals when a fact crosses a domain line. Call directly when two modules belong to the same subsystem. Overusing signals creates event soup and weakens traceability.

**Consequences**: Signal topology becomes the architecture diagram. Direct calls within a subsystem remain traceable. Constraint: never emit a signal to coordinate something in the same subsystem.

---

## AD-3: spawn/1 Is Generic

**Decision**: `spawn(team_name)` is a generic compile-and-launch operation. The team name resolves to a Workshop design. What the team does is determined by its prompts, not by a mode parameter.

**Context**: Current `TeamSpec.build(:mes | :pipeline | :planning)` puts caller knowledge inside the Workshop compiler. Three spawn implementations duplicate logic and diverge.

**Rationale**: The mistake is not having specialized orchestrators (pipeline needs DAG validation). The mistake is letting the compiler own their knowledge. `TeamSpec.compile(state, opts)` with injected `prompt_module` preserves testable prompt code while eliminating mode dispatch inside Workshop.

**Consequences**: Adding a new team type requires no TeamSpec changes. Constraint: each team record must carry a `prompt_module` binding.

---

## AD-4: Three Strata

**Decision**: (1) Pure model/query/compilation code -- no side effects. (2) Application orchestrators -- coordinate between model and runtime. (3) Runtime adapters -- tmux, filesystem, HTTP, bash at the outer edge.

**Context**: Filesystem paths, System.cmd, tmux control, and JSON mutation are spread through business logic. The effect boundary is too porous.

**Rationale**: Pure code is testable without process infrastructure. Orchestrators are testable by injecting adapter fakes. Adapters are integration-tested at their boundary. This is Elixir-native "functional core, imperative shell."

**Consequences**: PipelineMonitor becomes pure query module + Oban cron. TeamSpec.compile has no I/O. Adapter modules are the only places that touch the filesystem or shell.

---

## AD-5: Authority Model

**Decision**: Four authorities. (1) Ash resources for durable business state. (2) Registry + supervised processes for live runtime state. (3) External files for interoperability. (4) Signals carry facts, not ownership.

**Context**: Events, tmux state, JSONL files, registry entries, and Ash records all participate in truth without making authority explicit.

**Rationale**: When authority is ambiguous, every read requires reconciliation. Explicit authority means: canonical task status = PipelineTask (Ash). Agent alive? = Registry. External project tasks = tasks.jsonl (interop). No reconciliation needed.

**Consequences**: EventStream no longer auto-creates fleet entities. PipelineMonitor file reads become interop adapter. Ash is never bypassed for durable state writes.

---

## AD-6: Prompt Strategy Injection

**Decision**: `TeamSpec.compile/2` accepts a `prompt_module` option. Callers provide their own module implementing the prompt-building contract. The compiler has zero knowledge of MES, pipeline, or planning.

**Context**: `TeamSpec.build/N` hardcodes PlanningPrompts (Factory module) inside Workshop. CRITICAL RULES block copied verbatim in 11+ functions across three prompt modules.

**Rationale**: Prompt logic changes when the agent protocol changes. Compilation logic changes when the canvas model changes. These are separate axes of change. Option A (prompt_module per team) keeps prompts as versioned, testable Elixir code.

**Consequences**: Shared protocol blocks extracted into `Workshop.PromptProtocol`. Adding a new team type = one new prompt module + binding on Team record. No Factory imports in Workshop.

---

## AD-7: Typed Value Objects Over Stringly-Typed Identifiers

**Decision**: `RunRef`, `AgentId`, and `SessionRef` are explicit structs with `parse/1` and `format/1`. All pattern-matching on run kinds and session formats happens through these types.

**Context**: `runner.ex` has five functions each with three clauses on `:mes | :pipeline | :planning`. Two field names (`session_id` vs `agent_id`) for the same concept. String parsing by hand in multiple modules.

**Rationale**: A value object consolidates parsing to one place. `%RunRef{kind: :pipeline}` in function heads is correct Elixir dispatch. `"pipeline-" <> _` in multiple modules is fragile string archaeology.

**Consequences**: Runner mode dispatch collapses from 5x3 clause trees to RunRef-dispatched heads. New run kinds = one constructor, not six file edits.

---

## AD-8: Reliability Boundary -- Ash -> Oban -> PubSub

**Decision**: Three reliability layers. (1) Ash resources are durable truth. (2) Oban jobs are durable execution -- mandatory reactions insert Oban jobs directly from Ash notifiers/action bodies, not via PubSub subscribers. (3) PubSub signals are observational fanout only -- UI updates, logs, topology refreshes. Loss is acceptable.

**Context**: The original design routed mandatory work (cleanup, task reassignment, escalation) through PubSub -> subscriber -> Oban.insert. Codex identified the volatile hop: if the subscriber is down when the signal fires, the Oban job never gets enqueued. That's not delayed execution -- it's absent execution.

**Rationale**: If something must happen, persist intent durably first. If something is merely interesting, publish a signal. Ash notifiers fire after commit -- inserting an Oban job there is effectively an atomic durable enqueue. A periodic reconciler Oban cron checks for orphaned intents (e.g., Pipeline stuck in :active with no Runner).

**Consequences**: PubSub is demoted to observation-only. Cleanup/reassignment/webhook retry insert Oban jobs directly. The reconciler catches crash-window failures. Every Oban worker must be idempotent. Constraint: no mandatory work flows through PubSub alone.

---

## Tech Choices Summary

| Choice | Reason |
|--------|--------|
| **Ash** (not raw Ecto) | Actions are first-class: typed, described, policy-guarded, discoverable. Enables Discovery (planned) |
| **AshSqlite** | Single-node developer tool. No Postgres infrastructure required |
| **Oban** | Replaces MesScheduler, CronScheduler, PipelineMonitor health check GenServer patterns |
| **tmux** | Claude agents require PTY with visible output + text input. `tmux attach` = zero-cost debugging |
| **ETS for runtime projections** | O(1) concurrent reads without GenServer serialization. Multiple LiveViews read simultaneously |
| **PubSub for signals** | Subscriber set is dynamic and unknown to emitter at compile time. Fire-and-forget, correct for observational facts |
| **Bus for directed messages** | Sender has a specific target. Direct delivery with ETS log. Different system from PubSub signals |
