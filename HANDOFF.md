# ICHOR IV - Handoff

## Current Status: Wave 3 DONE, Codex Re-Review Pending (2026-03-21)

### Authoritative Architecture Documents

All implementation MUST align with `docs/architecture/` and `docs/plans/`. Codex reviews validate against them.

**Key docs**: `decisions.md` (AD-1 through AD-8), `architecture-audit.md` (findings X1/X2/O3/A1/A2/P1/DB2), `vertical-slices.md`, domain docs (workshop, factory, signals, infrastructure).

### Wave Status

**Wave 1 (Foundation)** -- COMPLETE, Codex 7.5/10

**Wave 2 (Oban Migration)** -- COMPLETE, Codex 8/10
- 3 GenServers -> Oban workers + plain APIs, reliability fixes applied

**Wave 3 (Structural)** -- COMPLETE, Codex re-review pending (6/10 initial -> fixes applied)
- W3-1 (X1): EventStream decoupled. SessionLifecycle subscriber. agent_lifecycle uses ETS not AgentProcess.
- W3-2 (AD-6): TeamSpec accepts prompt_module opt. PlanningPrompts alias removed from Workshop.
- W3-3 (AD-7): SCOPED, deferred. 20+ files, RunRef/AgentId/SessionRef structs. High effort.
- W3-4 (AD-8): TeamWatchdog inserts Oban jobs directly (no PubSub hop). 4 workers. RunCleanupSubscriber deleted.

**Codex W3 first review (6/10) findings and fixes:**
1. AD-8: RunCleanupSubscriber was volatile PubSub hop -> FIXED: TeamWatchdog inserts Oban directly
2. X1: agent_lifecycle still imported AgentProcess -> FIXED: uses EventStream ETS tables
3. AD-6: TeamSpec still hardcodes mode-specific logic -> ACCEPTED: import violation gone, full generic compiler is future work

**Wave 3 Commits:**
- `88e94a0` W3-2: AD-6 prompt strategy injection
- `da9fee2` W3-1: X1 EventStream decouple
- `c99d140` W3-4: AD-8 TeamWatchdog Oban cleanup
- (pending) X1+AD-8 fix commit

**Wave 4 (Large Structural)** -- W4-2 COMPLETE
- W4-1: PipelineMonitor elimination (623L GenServer -> pure query module + 2 Oban workers)
- W4-2: DONE -- CronJob moved to Factory, HITLInterventionEvent moved to SignalBus. ash.codegen: no schema changes. Build clean.

**Wave 3 deferred (W3-3 AD-7 Value Objects)** -- SCOPED
- RunRef: 6 functions with 3-clause dispatch, 10 modules parse strings by hand
- AgentId: session_id vs agent_id split across 8+ modules
- 20+ files, 3 new struct modules. Execute after W4 or as independent effort.

**Standing Tasks:**
- WX-tree: Update lib/ichor/TREE.md at end of each wave (OVERDUE)

### Protocols
- Architecture docs are authoritative (CLAUDE.md)
- ash-thinking skill before Ash agents, never ash-elixir-expert
- Codex reviews reference architecture docs
- Codex in codex-spar tmux, restart with --resume if exits
- Send prompts via temp file + tmux literal paste
- Every task cross-references governing architecture doc
- Keep-track at wave boundaries

### Build
- `mix compile --warnings-as-errors`: CLEAN
