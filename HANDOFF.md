# ICHOR IV - Handoff

## Current Status: Wave 2 DONE (8/10), Wave 3 Scoped (2026-03-21)

### Authoritative Architecture Documents

All implementation MUST align with these documents. They were carefully planned and researched across multiple codex sparring sessions. Codex reviews must validate changes against them.

**Reading order:**
1. `docs/architecture/decisions.md` -- AD-1 through AD-8, the load-bearing design choices
2. `docs/plans/GLOSSARY.md` -- canonical term definitions
3. `docs/plans/2026-03-21-vertical-slices.md` -- 9 use cases, cross-boundary problems
4. `docs/architecture/workshop-domain.md` -- Workshop CRUD, prompt mgmt, spawn convergence
5. `docs/architecture/factory-domain.md` -- project lifecycle, Oban worker plan
6. `docs/architecture/signals-domain.md` -- EventStore, Bus, AD-8 reliability model
7. `docs/architecture/infrastructure.md` -- host layer, tmux, CommPolicy
8. `docs/architecture/supervision-tree.md` + `memory-strategy.md` -- runtime concerns
9. `docs/architecture/target-file-structure.md` -- current-to-target file mapping

**Supporting:**
- `docs/plans/2026-03-21-architecture-blueprint.md` -- 8 ADs, ownership rules, gap analysis, 25-task wave plan
- `docs/plans/2026-03-21-architecture-audit.md` -- detailed findings by category
- `docs/plans/2026-03-21-actionable-findings.md` -- prioritized findings with file locations
- `docs/reviews/2026-03-21-codex-sparring.md` -- source of AD-8 reliability boundary

### Validation Rule
Every codex review prompt MUST include: "Validate against docs/architecture/decisions.md and the relevant domain doc." Agents must read the relevant architecture doc before implementing.

### Wave Status

**Wave 1 (Foundation)** -- COMPLETE, Codex 7.5/10

**Wave 2 (Oban Migration)** -- COMPLETE, Codex 8/10
- 3 GenServers replaced with Oban workers (MesTick, ScheduledJob, WebhookDeliveryWorker)
- Reliability fixes: Lite engine, idempotency guards, emit-after-commit, orphan cleanup
- Residual (accepted): webhook HTTP-before-DB inherent, startup-only recovery (not periodic reconciler)

**Wave 3 (Structural)** -- SCOPED, ready to execute
- W3-1: EventStream decouple (X1) -- 7 coupling points, new SessionLifecycle subscriber, AgentLifecycle deleted
- W3-2: TeamSpec prompt injection (AD-6) -- opts keyword with prompt_module:, 4 callers, PromptProtocol callback
- W3-3: Value objects RunRef/AgentId (AD-7) -- not yet scoped in detail, medium effort
- W3-4: TeamWatchdog Oban (X2/O3/AD-8) -- 4 new workers, 1 subscriber, consolidated signals

### Wave 3 Execution Plan

**Batch A** (parallel, independent files):
- W3-2: TeamSpec injection (5 files: team_spec.ex, prompt_protocol.ex, runner.ex, spawn.ex, planning_prompts.ex)
- W3-3: Value objects (defer detailed scope until Batch A done)

**Batch B** (after A, touches catalog.ex):
- W3-1: EventStream decouple (5 files + catalog.ex new signals)

**Batch C** (after B, also touches catalog.ex + new Oban queues):
- W3-4: TeamWatchdog Oban (7+ files: watchdog, 4 workers, 1 subscriber, catalog, application.ex)

**Rationale**: W3-1 and W3-4 both add signals to catalog.ex -- must be sequential. W3-4 is the AD-8 closure task (highest architectural value). W3-2 is independent of both.

### Wave 3 Detailed Scope (from scoping agents)

**W3-1 EventStream Decouple** (X1, decisions.md:183):
- 5 outbound couplings: EventStream/AgentLifecycle -> FleetSupervisor.spawn_agent, terminate_agent, create_team, disband_team, AgentProcess.update_fields
- 1 reverse: AgentProcess.terminate -> EventStream.tombstone_session
- Fix: New Infrastructure.Subscribers.SessionLifecycle subscribes to 4 signals
- Delete: agent_lifecycle.ex (content becomes subscriber body)
- Reverse fix: EventStream subscribes to existing :agent_stopped signal

**W3-2 TeamSpec Injection** (AD-6, decisions.md:68):
- 3 hardcoded prompt modules: PlanningPrompts (cross-domain!), PipelinePrompts, TeamPrompts
- 4 callers: runner.ex:300 (:mes), runner.ex:332 (corrective), spawn.ex:57 (:pipeline), spawn.ex:96 (:planning)
- Fix: Add opts keyword with prompt_module: to each build/N. Callers pass explicitly.
- PromptProtocol needs @callback build_prompt/2 added
- PlanningPrompts alias removed from Workshop namespace

**W3-4 TeamWatchdog Oban** (X2+O3+AD-8, audit:188/105, decisions:92):
- 4 direct cross-domain calls in dispatch/1: Pipeline.archive, PipelineTask.reset, FleetSupervisor.disband_team, Spawn.kill_session
- Inbox.write stays (correct per A3)
- Fix: 4 dispatch clauses emit signals instead
- 4 new idempotent Oban workers: ArchiveRunWorker, ResetRunTasksWorker, DisbandTeamWorker, KillSessionWorker
- 1 new RunCleanupSubscriber bridges signals to Oban.insert
- Consolidated signals: :run_cleanup_needed + :session_cleanup_needed

**Wave 4 (Large Structural)** -- after W3
- W4-1: Eliminate PipelineMonitor GenServer (P1)
- W4-2: Move Infrastructure Ash resources to correct domains (DB2)

**Standing Tasks:**
- WX-tree: Update lib/ichor/TREE.md at end of each wave

### Codex Review Protocol
- Codex runs in `codex-spar` tmux session
- Send prompts via temp file + literal paste (see memory/feedback/codex_tmux_prompts.md)
- Every review prompt must reference the architecture docs
- Wait for codex response before proceeding to next wave

### Agent Protocol
- Invoke `ash-thinking` skill BEFORE dispatching agents for Ash/Elixir work
- Never use `ash-elixir-expert` agents directly
- Split work by file scope, no two agents edit the same file
- Every task cross-references its governing architecture doc
- Verify build after agents complete, resolve conflicts

### Build
- `mix compile --warnings-as-errors`: CLEAN
