OpenAI Codex v0.101.0 (research preview)
--------
2026-03-21T14:08:54.821103Z ERROR rmcp::transport::worker: worker quit with fatal: Transport channel closed, when Client(reqwest::Error { kind: Request, url: "http://localhost/tidewave/mcp", source: hyper_util::client::legacy::Error(Connect, ConnectError("tcp connect error", 127.0.0.1:80, Os { code: 61, kind: ConnectionRefused, message: "Connection refused" })) })
workdir: /Users/xander/code/www/kardashev/observatory
model: gpt-5.4
provider: openai
approval: never
sandbox: workspace-write [workdir, /tmp, $TMPDIR]
reasoning effort: medium
reasoning summaries: auto
session id: 019d10ba-3df4-75b1-8db5-fa97253c8158
--------
user
You are in a persistent sparring session reviewing the ICHOR IV architecture blueprint. Read docs/plans/2026-03-21-architecture-blueprint.md first. Then read docs/plans/GLOSSARY.md and docs/diagrams/architecture.md. DO NOT modify any files. Output your analysis to STDOUT only.

Your role: challenge every decision. Find weaknesses. Propose alternatives. Be the skeptic.

After reading, respond with:
1. Which decisions are STRONG and why
2. Which decisions are WEAK and why  
3. What is MISSING that should be decided
4. Your single biggest concern about this architecture
5. One question you would ask the architect

End your response with SPARRING_ROUND_1_COMPLETE so we know you are done.
mcp: playwright starting
mcp: tidewave starting
mcp: codex_apps starting
mcp: tidewave failed: MCP client for `tidewave` failed to start: MCP startup failed: handshaking with MCP server failed: Send message error Transport [rmcp::transport::worker::WorkerTransport<rmcp::transport::streamable_http_client::StreamableHttpClientWorker<reqwest::async_impl::client::Client>>] error: Client error: error sending request for url (http://localhost/tidewave/mcp), when send initialize request
2026-03-21T14:08:54.854393Z ERROR codex_core::rollout::list: state db missing rollout path for thread 019d00f7-9440-7641-9bf4-e93216f8b1d4
2026-03-21T14:08:54.878522Z ERROR codex_core::rollout::list: state db missing rollout path for thread 019d06f9-439c-75b0-90dd-66894bb227c0
mcp: codex_apps ready
mcp: playwright ready
mcp startup: ready: codex_apps, playwright; failed: tidewave
codex
I’m reading the three architecture docs first, then I’ll produce a skeptical review with explicit strengths, weaknesses, missing decisions, and the highest-risk concern.
exec
/bin/zsh -lc "sed -n '1,240p' docs/plans/GLOSSARY.md" in /Users/xander/code/www/kardashev/observatoryexec
/bin/zsh -lc "sed -n '1,240p' docs/plans/2026-03-21-architecture-blueprint.md" in /Users/xander/code/www/kardashev/observatoryexec
/bin/zsh -lc "sed -n '1,260p' docs/diagrams/architecture.md" in /Users/xander/code/www/kardashev/observatory succeeded in 52ms:
# ICHOR IV Architecture Diagrams

Related: [Vertical Slices](../plans/2026-03-21-vertical-slices.md) | [Architecture Audit](../plans/2026-03-21-architecture-audit.md) | [Glossary](../plans/GLOSSARY.md) | [Database Schema](database-schema.md)

---

## Concepts: What Signals Actually Is

Signals is the nervous system. Everything that happens in the app becomes a signal. Anything that needs to react subscribes. No direct cross-domain calls needed.

```mermaid
graph LR
    subgraph "Things That Happen"
        A[agent starts working]
        B[agent goes silent]
        C[run completes]
        D[task gets claimed]
        E[operator sends message]
    end

 succeeded in 52ms:
# ICHOR IV Glossary

Canonical definitions. When two words could mean the same thing, this file says which one we use and what the other one means.

Related: [Database Schema](../diagrams/database-schema.md) | [Architecture Diagrams](../diagrams/architecture.md)

---

## Overloaded Terms (same word, different meaning by context)

| Word | In Factory | In Workshop | In Infrastructure | In general |
|------|-----------|------------|-------------------|-----------|
| **Project** | A planning brief being turned into requirements. Has artifacts, a roadmap, and a lifecycle status | Not used | Not used | A git repository. External projects have their own `tasks.jsonl` |
| **Team** | A runtime group of agents executing a run. Ephemeral -- exists only while the run is alive | A saved team design on the canvas. Persistent -- agents, spawn links, comm rules | The OTP grouping that lets us list members and disband | Never a human team |
| **Agent** | Not used directly | A live Claude instance viewed through the fleet. Also: an agent type (a reusable template for configuring agents) | The BEAM process that holds an agent's mailbox, backend, and state | A Claude Code instance running in tmux |
| **Task** | A unit of work in a pipeline. One line in `tasks.jsonl`. Has dependencies, an owner, a status | Not used | Not used | Never an Elixir `Task` or Oban job |
| **Pipeline** | A single build execution attempt. Groups tasks into a run | Not used | Not used | Never a Unix pipe or data pipeline |
| **Run** | An execution lifecycle with a kind (mes/pipeline/planning), a session, and a timeline | Not applicable -- workshop launches are fire-and-forget, no lifecycle monitor | Not used | Not "running" as in process state |
| **Session** | The tmux session that hosts a run's agent windows (e.g., `"mes-abc123"`) | Not used | The tmux session as an infrastructure concern | Not a web session or Phoenix session |
| **Status** | Varies per concept: pipeline (active/completed/failed/archived), task (pending/in_progress/completed/failed), project (proposed/in_progress/compiled/loaded/failed) | Not used for teams (they're ephemeral) | Agent (active/idle/ended), webhook (pending/delivered/failed/dead) | Each concept has its own status values. Never interchangeable |
 succeeded in 52ms:
# ICHOR IV Architecture Blueprint

**Date**: 2026-03-21
**Status**: Draft -- pending codex sparring review

Related: [Glossary](GLOSSARY.md) | [Diagrams](../diagrams/architecture.md) | [Database Schema](../diagrams/database-schema.md) | [Codex Review 1](../reviews/2026-03-21-codex-review-1.md) | [Codex Review 2](../reviews/2026-03-21-codex-review-2.md)

---

## Part 1: Architectural Decisions

### AD-1: Ash as Business Boundary

**Decision**: Ash domains are the exclusive public API for all durable business state. Callers invoke domain-owned actions; they do not call resource modules directly or construct changesets outside a resource's own action blocks.

**Context**: Ash actions are the composable unit of work that Discovery will expose for dynamic workflow composition. An action with a description, typed arguments, typed return, and a policy is discoverable, auditable, and pipeable.

**Rationale**: 90% declared, 10% imperative. Ash makes that achievable only if the boundary is respected. Raw `Ash.create/1` calls from business logic are not discoverable. `define` in the code interface is.

**Consequences**: Enables Discovery. Policies become enforceable. Actions become directly composable in UI-built workflows. Constraint: no direct resource module calls from outside the owning domain.
codex
The core blueprint is loaded. I’m pulling the rest of the diagram doc so the critique isn’t biased by a partial topology view.
exec
/bin/zsh -lc "sed -n '261,520p' docs/diagrams/architecture.md" in /Users/xander/code/www/kardashev/observatory succeeded in 51ms:
    end

    subgraph SignalBus["SignalBus Domain (reactive backbone)"]
        direction TB
        Event[Event]
        Ops[Operations]
        ES[EventStream store]
        AW[AgentWatchdog]
        Bus[Bus delivery]
        Buffer[Buffer]
    end

    subgraph Infra["Infrastructure (host layer)"]
        direction TB
        FS[FleetSupervisor]
        AP[AgentProcess]
        TL[TeamLaunch]
        Tmux[Tmux adapter]
        HITL[HITLRelay]
        Reg[Registry]

thinking
**Clarifying documentation details**

I think I just need to pull the answer from the documentation. I want it to be concise but still substantive. There seems to be a contradiction: the diagrams suggest that signals are only coupled, but AD-2 mentions direct interactions within the subsystem. I might need to consider the strength of these interactions—either strong or weak. It's a bit tricky, but I'll get it sorted!
codex
1. **Strong decisions and why**

- **AD-4 Three Strata** is strong. It is the clearest line in the document: pure code, orchestrators, adapters. That directly addresses the current path/shell/tmux leakage and gives a test strategy that is actually enforceable.
- **AD-5 Authority Model** is strong. Explicitly naming Ash, Registry/processes, files, and signals as separate authorities prevents the worst class of architecture drift: “everything is partly true everywhere.”
- **AD-1 Ash as Business Boundary** is strong if enforced rigorously. Tying durable business operations to named Ash actions is coherent with the stated Discovery goal, and it gives policies, typed interfaces, and auditability a real home.
- **AD-7 Typed value objects** is strong. This is a low-risk, high-leverage cleanup that should remove a lot of mode/session/string branching noise.
- **The gap analysis itself** is strong. It is unusually concrete, names specific existing failures, and maps them to implementation waves instead of staying aspirational.

2. **Weak decisions and why**

- **“Signals is the only coupling point between domains” in the diagram is weaker than AD-2.** The blueprint contradicts itself. AD-2 says direct calls are valid within cohesive subsystems; the diagram says no direct cross-domain calls needed and “only coupling point.” Those are materially different rules. This ambiguity will produce architecture by slogan.
- **`spawn(team_name)` as the universal abstraction is weak.** It hides too much variance behind one verb. Planning, pipeline, workshop launch, and MES tick do not share the same preconditions, lifecycle, idempotency, monitoring, or outputs. A single generic entrypoint risks becoming a god-orchestrator with invisible branching moved out to subscribers and prompt modules.
- **Prompt strategy injection via `prompt_module` is weaker than it looks.** It removes one form of coupling but creates a new one: behavior critical to system correctness is pushed into arbitrary prompt modules with unclear versioning, compatibility, validation, and migration rules. “What the team does is determined by its prompts” is too loose for core execution semantics.
- **PubSub for signals as stated is weak for anything operationally important.** “Fire-and-forget with no backpressure” is fine for observational UI updates, but the same document also wants signals to drive cleanup, watchdog reactions, task reassignment, and lifecycle handling. That is no longer merely observational.
- **Oban replacing timer GenServers is only partially argued.** It is plausible for retries and scheduling, but the blueprint does not separate scheduled work from stateful monitoring loops clearly enough. Some current GenServers may be badly designed, but that does not prove all should become jobs.
- **The ownership table has blurry boundaries around Archon, SignalBus, and Infrastructure.** Archon “owns cleanup orchestration” but domain-specific cleanup should emit signals; SignalBus owns message delivery but not fleet mutation; Infrastructure emits lifecycle signals but must not own business logic. Those lines still leave too much room for “just one call” exceptions.

3. **What is missing that should be decided**

- **Failure semantics for signals.** Which signals are best-effort vs guaranteed? Which require durable delivery, deduplication, ordering, or replay?
- **Transactional boundaries.** When an Ash action emits a signal, what is the consistency model? After commit only? Outbox pattern? Immediate PubSub plus eventual reconciliation?
- **Idempotency rules.** Especially for spawn, cleanup, agent discovery, task reassignment, and webhook/event ingestion.
- **Concurrency model.** What happens when two triggers try to spawn the same team, or two subscribers react to the same fact?
- **Error ownership.** Which layer translates adapter failures into domain failures? Right now the strata exist, but exception and retry policy do not.
- **Lifecycle model for runs vs workshop launches.** The glossary says workshop launches are fire-and-forget with no lifecycle monitor. That feels like an unexamined exception, not a principled choice.
- **Security/actor propagation details.** “Actor threaded through all call sites” is noted as a gap, but the architecture does not decide what the actor model actually is for agents, operator relay, architect, and automated jobs.
- **Schema evolution/versioning for prompts and TeamSpec.** If team behavior is prompt-defined, version compatibility is architecture, not implementation detail.
- **Recovery/rebuild strategy.** On restart, what is reconstructed from Ash, what is rediscovered from tmux/Registry/files, and what is intentionally lost?

4. **Single biggest concern**

The biggest concern is that the architecture is trying to use **signals as a decoupling ideal and also as an operational control plane** without deciding reliability semantics. That is the danger zone. Best-effort PubSub is fine for observation; it is not automatically fine for task reassignment, cleanup orchestration, spawn constraints, escalation, and lifecycle management. If that boundary is not nailed down, the system will become nondeterministic under failure.

5. **One question to ask the architect**

Which cross-domain facts are merely **observational signals**, and which are actually **commands or required workflow steps** that must be delivered exactly-once or at-least-once with idempotency?

SPARRING_ROUND_1_COMPLETE
tokens used
23.510
1. **Strong decisions and why**

- **AD-4 Three Strata** is strong. It is the clearest line in the document: pure code, orchestrators, adapters. That directly addresses the current path/shell/tmux leakage and gives a test strategy that is actually enforceable.
- **AD-5 Authority Model** is strong. Explicitly naming Ash, Registry/processes, files, and signals as separate authorities prevents the worst class of architecture drift: “everything is partly true everywhere.”
- **AD-1 Ash as Business Boundary** is strong if enforced rigorously. Tying durable business operations to named Ash actions is coherent with the stated Discovery goal, and it gives policies, typed interfaces, and auditability a real home.
- **AD-7 Typed value objects** is strong. This is a low-risk, high-leverage cleanup that should remove a lot of mode/session/string branching noise.
- **The gap analysis itself** is strong. It is unusually concrete, names specific existing failures, and maps them to implementation waves instead of staying aspirational.

2. **Weak decisions and why**

- **“Signals is the only coupling point between domains” in the diagram is weaker than AD-2.** The blueprint contradicts itself. AD-2 says direct calls are valid within cohesive subsystems; the diagram says no direct cross-domain calls needed and “only coupling point.” Those are materially different rules. This ambiguity will produce architecture by slogan.
- **`spawn(team_name)` as the universal abstraction is weak.** It hides too much variance behind one verb. Planning, pipeline, workshop launch, and MES tick do not share the same preconditions, lifecycle, idempotency, monitoring, or outputs. A single generic entrypoint risks becoming a god-orchestrator with invisible branching moved out to subscribers and prompt modules.
- **Prompt strategy injection via `prompt_module` is weaker than it looks.** It removes one form of coupling but creates a new one: behavior critical to system correctness is pushed into arbitrary prompt modules with unclear versioning, compatibility, validation, and migration rules. “What the team does is determined by its prompts” is too loose for core execution semantics.
- **PubSub for signals as stated is weak for anything operationally important.** “Fire-and-forget with no backpressure” is fine for observational UI updates, but the same document also wants signals to drive cleanup, watchdog reactions, task reassignment, and lifecycle handling. That is no longer merely observational.
- **Oban replacing timer GenServers is only partially argued.** It is plausible for retries and scheduling, but the blueprint does not separate scheduled work from stateful monitoring loops clearly enough. Some current GenServers may be badly designed, but that does not prove all should become jobs.
- **The ownership table has blurry boundaries around Archon, SignalBus, and Infrastructure.** Archon “owns cleanup orchestration” but domain-specific cleanup should emit signals; SignalBus owns message delivery but not fleet mutation; Infrastructure emits lifecycle signals but must not own business logic. Those lines still leave too much room for “just one call” exceptions.

3. **What is missing that should be decided**

- **Failure semantics for signals.** Which signals are best-effort vs guaranteed? Which require durable delivery, deduplication, ordering, or replay?
- **Transactional boundaries.** When an Ash action emits a signal, what is the consistency model? After commit only? Outbox pattern? Immediate PubSub plus eventual reconciliation?
- **Idempotency rules.** Especially for spawn, cleanup, agent discovery, task reassignment, and webhook/event ingestion.
- **Concurrency model.** What happens when two triggers try to spawn the same team, or two subscribers react to the same fact?
- **Error ownership.** Which layer translates adapter failures into domain failures? Right now the strata exist, but exception and retry policy do not.
- **Lifecycle model for runs vs workshop launches.** The glossary says workshop launches are fire-and-forget with no lifecycle monitor. That feels like an unexamined exception, not a principled choice.
- **Security/actor propagation details.** “Actor threaded through all call sites” is noted as a gap, but the architecture does not decide what the actor model actually is for agents, operator relay, architect, and automated jobs.
- **Schema evolution/versioning for prompts and TeamSpec.** If team behavior is prompt-defined, version compatibility is architecture, not implementation detail.
- **Recovery/rebuild strategy.** On restart, what is reconstructed from Ash, what is rediscovered from tmux/Registry/files, and what is intentionally lost?

4. **Single biggest concern**

The biggest concern is that the architecture is trying to use **signals as a decoupling ideal and also as an operational control plane** without deciding reliability semantics. That is the danger zone. Best-effort PubSub is fine for observation; it is not automatically fine for task reassignment, cleanup orchestration, spawn constraints, escalation, and lifecycle management. If that boundary is not nailed down, the system will become nondeterministic under failure.

5. **One question to ask the architect**

Which cross-domain facts are merely **observational signals**, and which are actually **commands or required workflow steps** that must be delivered exactly-once or at-least-once with idempotency?

SPARRING_ROUND_1_COMPLETE
OpenAI Codex v0.101.0 (research preview)
--------
2026-03-21T14:17:54.650647Z ERROR rmcp::transport::worker: worker quit with fatal: Transport channel closed, when Client(reqwest::Error { kind: Request, url: "http://localhost/tidewave/mcp", source: hyper_util::client::legacy::Error(Connect, ConnectError("tcp connect error", 127.0.0.1:80, Os { code: 61, kind: ConnectionRefused, message: "Connection refused" })) })
workdir: /Users/xander/code/www/kardashev/observatory
model: gpt-5.4
provider: openai
approval: never
sandbox: workspace-write [workdir, /tmp, $TMPDIR]
reasoning effort: medium
reasoning summaries: auto
session id: 019d10c2-7afe-7892-99ca-1dd69fb0d184
--------
user
SPARRING ROUND 2. You are continuing the architecture review of ICHOR IV. DO NOT modify files. STDOUT only.

Round 1 raised these challenges. Here are my responses:

**Diagram contradiction (AD-2 vs "only coupling point")**
You are right. The diagram oversimplifies. AD-2 is the rule: signals for cross-boundary facts, direct calls within cohesive subsystems. The diagram will be corrected. Within a domain, direct calls are not just acceptable -- they are preferred. Signals become noise inside a subsystem.

**spawn/1 hiding variance**
The variance is real but mislocated. spawn/1 does not hide preconditions -- callers still do their own preflight (Factory validates DAGs before calling spawn). spawn/1 is the compile-and-launch primitive after preflight. The variance in lifecycle (Runner vs fire-and-forget) is team metadata, not a spawn concern. But you are right that the boundary between "caller preflight" and "spawn" needs explicit definition. What is the contract?

**prompt_module versioning**
Fair point. Prompt modules are code, so they version with the codebase. But the binding (Team record -> module atom) can drift if a module is renamed or deleted. The validation should be: at compile time, verify every prompt_module binding resolves to a loaded module. This is a compile-time check, not a runtime hope.

**PubSub reliability for operational signals**
This is your strongest challenge. The answer: operational reactions (cleanup, task reassignment, escalation) go through Oban. The signal triggers the Oban.insert. Oban provides at-least-once delivery with idempotent workers. PubSub is the notification layer; Oban is the reliability layer. Two-phase: signal fires -> subscriber enqueues Oban job -> job executes with retry. PubSub loss means delayed execution (next poll or manual trigger), not permanent loss.

**Missing decisions you identified:**
- Failure semantics: agreed, needs AD-8. Signals are best-effort notification. Durable execution is Oban. No outbox pattern needed because Ash notifiers fire after commit.
- Idempotency: agreed. Every Oban worker must be idempotent. spawn checks "already running" before proceeding. cleanup checks "already archived."
- Concurrency: spawn constraint is a pattern match in a subscriber (as discussed). Two concurrent spawns of "mes" -- the subscriber checks Registry, only one proceeds.
- Recovery: on restart, Ash state survives (SQLite). Registry/ETS is lost and rebuilt from events + tmux discovery. Intentionally lost: in-flight escalation state, message log (ETS). This should be documented.
- Actor model: three actors -- Architect (human via dashboard), Operator (relay persona), Agent (Claude via MCP). Archon is an Agent with elevated permissions. Oban jobs run as system actor.

**Your question about observational vs command signals:**
All signals are observational. None are commands. The distinction: a signal says "this happened." A subscriber decides to enqueue an Oban job. The Oban job is the command. Signals never carry "do this" semantics -- they carry "this occurred" semantics. The subscriber bridges observation to action.

Now your turn:
1. Do my responses resolve your concerns or create new ones?
2. Is the two-phase pattern (signal -> Oban) sufficient for reliability?
3. What would you change about the 5-wave execution plan?
4. Is there a simpler architecture that achieves the same goals?

End with SPARRING_ROUND_2_COMPLETE.
mcp: tidewave starting
mcp: playwright starting
mcp: codex_apps starting
mcp: tidewave failed: MCP client for `tidewave` failed to start: MCP startup failed: handshaking with MCP server failed: Send message error Transport [rmcp::transport::worker::WorkerTransport<rmcp::transport::streamable_http_client::StreamableHttpClientWorker<reqwest::async_impl::client::Client>>] error: Client error: error sending request for url (http://localhost/tidewave/mcp), when send initialize request
2026-03-21T14:17:54.686472Z ERROR codex_core::rollout::list: state db missing rollout path for thread 019d00f7-9440-7641-9bf4-e93216f8b1d4
2026-03-21T14:17:54.712497Z ERROR codex_core::rollout::list: state db missing rollout path for thread 019d06f9-439c-75b0-90dd-66894bb227c0
mcp: playwright ready
mcp: codex_apps ready
mcp startup: ready: playwright, codex_apps; failed: tidewave
codex
1. Your responses resolve some concerns, but they also expose the real fault lines more clearly.

- `AD-2` is now coherent. "Signals across boundaries, direct calls within cohesive subsystems" is a defensible rule.
- `spawn/1` is better framed, but the contract still needs to be written down precisely. Right now it sounds like "preflight elsewhere, compile-and-launch here," which is fine, but only if you define:
  - required preconditions
  - what `spawn/1` re-validates defensively
  - what invariants it guarantees after success/failure
- `prompt_module` is only solved if the binding is static code/config. If the `Team` record is persisted data, compile-time validation is not enough. You also need boot-time or changeset-time validation that the module exists and implements the required behaviour.
- The PubSub answer is the main place where the concern is not resolved. `signal -> subscriber -> Oban.insert` is not reliable enough for operational work because the volatile hop is before the durable hop. If the subscriber is down, lagging, or the PubSub delivery is missed, the Oban job is never enqueued. That is not "delayed execution"; that is "possibly absent execution unless some reconciler notices later."

2. The two-phase pattern is not sufficient for reliability on its own.

It is sufficient for:
- UI refresh
- non-critical observability
- soft-triggered background work with acceptable lag and reconciliation

It is not sufficient for:
- cleanup guarantees
- reassignment guarantees
- escalation guarantees
- exactly-once intent capture

The weak point is not Oban. Oban is fine. The weak point is the non-durable bridge into Oban.

If you want operational reliability, the durable intent needs to exist before or with the triggering state transition. The usual options are:

- Write directly to Oban in the command path after commit.
- Use an outbox table and a dispatcher.
- Run a reconciler/poller that derives missing jobs from durable Ash state.

Given your constraints, the simplest acceptable answer is probably:
- PubSub for notification only.
- Oban insertion from the state-changing path when the reaction is mandatory.
- Periodic reconciler for repair.

That removes the "hope the subscriber was awake" problem.

3. On the 5-wave plan: I would change the ordering, even without seeing the exact draft.

Move these to Wave 1:
- `spawn/1` contract
- failure semantics (`AD-8`)
- idempotency rules
- concurrency control model
- recovery model

Those are architecture-defining, not implementation cleanup.

Move these to Wave 2:
- durable execution path for operational reactions
- uniqueness/locking strategy for spawn
- reconciler design

Delay these until later:
- diagram cleanup
- actor taxonomy refinements
- team metadata/lifecycle polish

Also, I would reject "subscriber checks Registry, only one proceeds" as the concurrency answer unless this is strictly single-node and non-critical. Registry/ETS is process-local and volatile. If duplicate spawn matters, use a durable uniqueness boundary:
- Oban unique job
- DB uniqueness/lease row
- transactional state transition

4. A simpler architecture does exist.

I would simplify to this:

- Direct calls inside a subsystem.
- Ash state as source of truth.
- Oban as the only command execution plane.
- PubSub only for UI/observability, never as the required bridge to durable work.
- Registry/ETS only as caches and live-process indexes, never as correctness boundaries.
- Reconciler job that periodically repairs drift between Ash state and runtime state.

That yields:
- fewer semantic layers
- clearer failure handling
- simpler restart story
- less argument about whether a signal was "observational" or "operationally important"

The core simplification is this: if something must happen, persist intent durably first. If something is merely interesting, publish a signal.

So the short version is:

- `AD-2`: resolved
- `spawn/1`: mostly resolved, needs a hard contract
- `prompt_module`: partially resolved, but only for static bindings
- `signal -> Oban`: not enough for reliable ops without a durable enqueue path or reconciler
- concurrency/recovery: still under-specified at the durability boundary

SPARRING_ROUND_2_COMPLETE
tokens used
13.124
1. Your responses resolve some concerns, but they also expose the real fault lines more clearly.

- `AD-2` is now coherent. "Signals across boundaries, direct calls within cohesive subsystems" is a defensible rule.
- `spawn/1` is better framed, but the contract still needs to be written down precisely. Right now it sounds like "preflight elsewhere, compile-and-launch here," which is fine, but only if you define:
  - required preconditions
  - what `spawn/1` re-validates defensively
  - what invariants it guarantees after success/failure
- `prompt_module` is only solved if the binding is static code/config. If the `Team` record is persisted data, compile-time validation is not enough. You also need boot-time or changeset-time validation that the module exists and implements the required behaviour.
- The PubSub answer is the main place where the concern is not resolved. `signal -> subscriber -> Oban.insert` is not reliable enough for operational work because the volatile hop is before the durable hop. If the subscriber is down, lagging, or the PubSub delivery is missed, the Oban job is never enqueued. That is not "delayed execution"; that is "possibly absent execution unless some reconciler notices later."

2. The two-phase pattern is not sufficient for reliability on its own.

It is sufficient for:
- UI refresh
- non-critical observability
- soft-triggered background work with acceptable lag and reconciliation

It is not sufficient for:
- cleanup guarantees
- reassignment guarantees
- escalation guarantees
- exactly-once intent capture

The weak point is not Oban. Oban is fine. The weak point is the non-durable bridge into Oban.

If you want operational reliability, the durable intent needs to exist before or with the triggering state transition. The usual options are:

- Write directly to Oban in the command path after commit.
- Use an outbox table and a dispatcher.
- Run a reconciler/poller that derives missing jobs from durable Ash state.

Given your constraints, the simplest acceptable answer is probably:
- PubSub for notification only.
- Oban insertion from the state-changing path when the reaction is mandatory.
- Periodic reconciler for repair.

That removes the "hope the subscriber was awake" problem.

3. On the 5-wave plan: I would change the ordering, even without seeing the exact draft.

Move these to Wave 1:
- `spawn/1` contract
- failure semantics (`AD-8`)
- idempotency rules
- concurrency control model
- recovery model

Those are architecture-defining, not implementation cleanup.

Move these to Wave 2:
- durable execution path for operational reactions
- uniqueness/locking strategy for spawn
- reconciler design

Delay these until later:
- diagram cleanup
- actor taxonomy refinements
- team metadata/lifecycle polish

Also, I would reject "subscriber checks Registry, only one proceeds" as the concurrency answer unless this is strictly single-node and non-critical. Registry/ETS is process-local and volatile. If duplicate spawn matters, use a durable uniqueness boundary:
- Oban unique job
- DB uniqueness/lease row
- transactional state transition

4. A simpler architecture does exist.

I would simplify to this:

- Direct calls inside a subsystem.
- Ash state as source of truth.
- Oban as the only command execution plane.
- PubSub only for UI/observability, never as the required bridge to durable work.
- Registry/ETS only as caches and live-process indexes, never as correctness boundaries.
- Reconciler job that periodically repairs drift between Ash state and runtime state.

That yields:
- fewer semantic layers
- clearer failure handling
- simpler restart story
- less argument about whether a signal was "observational" or "operationally important"

The core simplification is this: if something must happen, persist intent durably first. If something is merely interesting, publish a signal.

So the short version is:

- `AD-2`: resolved
- `spawn/1`: mostly resolved, needs a hard contract
- `prompt_module`: partially resolved, but only for static bindings
- `signal -> Oban`: not enough for reliable ops without a durable enqueue path or reconciler
- concurrency/recovery: still under-specified at the durability boundary

SPARRING_ROUND_2_COMPLETE
OpenAI Codex v0.101.0 (research preview)
--------
workdir: /Users/xander/code/www/kardashev/observatory
model: gpt-5.4
provider: openai
approval: never
sandbox: workspace-write [workdir, /tmp, $TMPDIR]
reasoning effort: medium
reasoning summaries: auto
session id: 019d10c4-e107-7222-a813-3c6eed71104f
--------
user
SPARRING ROUND 3 (final). ICHOR IV architecture. DO NOT modify files. STDOUT only. Keep it short.

You won the reliability argument. The two-phase pattern (signal -> subscriber -> Oban) has a volatile hop that can lose mandatory work. Here is the corrected model:

**Mandatory reactions**: Oban.insert directly in the Ash notifier or action body. No PubSub hop. Examples: run cleanup, task reassignment, webhook delivery retry. The Oban job IS the durable intent.

**Observational reactions**: PubSub signal -> subscriber updates UI, ETS, or logs. Loss is acceptable. Examples: dashboard refresh, topology update, message log.

**Reconciler**: periodic Oban cron that checks Ash state for orphaned intents (e.g., a Pipeline stuck in :active with no running Runner). Catches anything the mandatory path missed due to crash during Oban.insert.

This gives us: Ash (truth) -> Oban (durable execution) -> PubSub (observation). Three layers, clear reliability boundary.

On your other points:
- **spawn/1 contract**: agreed, needs to be written. Will add as AD-8.
- **prompt_module validation**: boot-time check + changeset validation on Team, not just compile-time.
- **Concurrency**: this IS single-node (developer tool on macOS). Registry check is sufficient. Oban unique jobs as belt-and-suspenders.
- **Wave reordering**: accepted. Architecture decisions (contracts, failure semantics, idempotency) move to Wave 1. Implementation cleanup moves later.

Final questions:
1. Does this three-layer model (Ash -> Oban -> PubSub) resolve your biggest concern?
2. Any remaining architectural risk you see?
3. Rate the blueprint 1-10 after these three rounds of sparring.

End with SPARRING_COMPLETE.
mcp: playwright starting
mcp: tidewave starting
mcp: codex_apps starting
2026-03-21T14:20:31.865400Z ERROR rmcp::transport::worker: worker quit with fatal: Transport channel closed, when Client(reqwest::Error { kind: Request, url: "http://localhost/tidewave/mcp", source: hyper_util::client::legacy::Error(Connect, ConnectError("tcp connect error", 127.0.0.1:80, Os { code: 61, kind: ConnectionRefused, message: "Connection refused" })) })
mcp: tidewave failed: MCP client for `tidewave` failed to start: MCP startup failed: handshaking with MCP server failed: Send message error Transport [rmcp::transport::worker::WorkerTransport<rmcp::transport::streamable_http_client::StreamableHttpClientWorker<reqwest::async_impl::client::Client>>] error: Client error: error sending request for url (http://localhost/tidewave/mcp), when send initialize request
2026-03-21T14:20:31.898828Z ERROR codex_core::rollout::list: state db missing rollout path for thread 019d00f7-9440-7641-9bf4-e93216f8b1d4
2026-03-21T14:20:31.922898Z ERROR codex_core::rollout::list: state db missing rollout path for thread 019d06f9-439c-75b0-90dd-66894bb227c0
mcp: codex_apps ready
mcp: playwright ready
mcp startup: ready: codex_apps, playwright; failed: tidewave
codex
1. Yes. `Ash -> Oban -> PubSub` resolves the core reliability flaw. Mandatory work now has a durable boundary, and PubSub is correctly demoted to observational fanout.

2. Remaining architectural risks:
- Crash window around state change vs `Oban.insert`: if those are not made atomic enough, the reconciler becomes part of normal correctness, not just recovery.
- Idempotency discipline: every mandatory handler and reconciler path must tolerate duplicate execution cleanly.
- Ownership of intent creation: be explicit about when intent is created in the action/notifier lifecycle so ordering is deterministic.
- `spawn/1` contract is still a real gap until written, because runner semantics drive recovery and reconciliation rules.

3. Rating: `8.5/10`.

Biggest improvement is the reliability boundary is now coherent. What keeps it below 9 is mostly execution-detail risk, not conceptual architecture risk.

SPARRING_COMPLETE
tokens used
11.693
1. Yes. `Ash -> Oban -> PubSub` resolves the core reliability flaw. Mandatory work now has a durable boundary, and PubSub is correctly demoted to observational fanout.

2. Remaining architectural risks:
- Crash window around state change vs `Oban.insert`: if those are not made atomic enough, the reconciler becomes part of normal correctness, not just recovery.
- Idempotency discipline: every mandatory handler and reconciler path must tolerate duplicate execution cleanly.
- Ownership of intent creation: be explicit about when intent is created in the action/notifier lifecycle so ordering is deterministic.
- `spawn/1` contract is still a real gap until written, because runner semantics drive recovery and reconciliation rules.

3. Rating: `8.5/10`.

Biggest improvement is the reliability boundary is now coherent. What keeps it below 9 is mostly execution-detail risk, not conceptual architecture risk.

SPARRING_COMPLETE
