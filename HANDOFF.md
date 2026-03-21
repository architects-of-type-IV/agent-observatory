# ICHOR IV - Handoff

## Current Status: Architecture Understanding Complete (2026-03-21)

### Session Summary
Three phases in one session: (1) tactical fixes, (2) structural decomposition, (3) deep architecture understanding.

### Phase 1: Tactical Fixes (complete)
- Ash idiomacy audit: 16 high findings fixed across 5 domains, 33 resources
- Code review: 20 findings fixed (7 critical security/crash, 13 high)
- Frontend dead code: 8 files removed, 15+ dead functions cleaned
- Migration applied: task_count removed from pipelines
- PR #1 merged: AgentProcess decomposed into 6 helpers + inbox fix

### Phase 2: Module Decompositions (complete)
- Runner -> +HealthChecker, +Exporter, +Modes (806->577)
- AgentWatchdog -> +EscalationEngine, +PaneScanner (580->487)
- EventStream -> +Normalizer, +AgentLifecycle (562->320)
- Spawn -> +Loader, +Validator, +WorkerGroups (521->220)

### Phase 3: Architecture Understanding (complete, documented)
Key insights discovered through dialogue with user:

1. **spawn/1 is generic**: team name -> compile Workshop design -> launch. Page-independent. What the team does is defined by prompts configured in Workshop. Current :mes/:pipeline/:planning are team configs, not code branches.

2. **Signals is the reactive backbone**: producers emit, subscribers react. No direct cross-domain calls. Constraints on spawning are just pattern matches in subscriber handle_info clauses -- no "Policy" abstraction needed.

3. **Workshop owns design, not execution**: the canvas configures agents, prompts, spawn links, comm rules. Spawn compiles and launches. The prompt builder belongs in Workshop per agent slot.

4. **Don't name what Elixir already has**: pattern matching in a subscriber IS the constraint mechanism. No SpawnPolicy, no PolicyEngine. Concepts exist in conversation but not as modules.

5. **Discovery (planned)**: Ichor.Discovery will expose all Ash actions by Domain for dynamic workflow composition in UI. Actions become pluggable pipeline steps.

### Documentation Created
- `docs/plans/2026-03-21-architecture-audit.md` -- findings + execution waves
- `docs/plans/2026-03-21-vertical-slices.md` -- use cases + spawn insight + boundary problems
- `docs/plans/GLOSSARY.md` -- 50+ terms with overloaded term disambiguation
- `docs/plans/INDEX.md` -- active docs + archive pointer
- `docs/diagrams/architecture.md` -- 15 mermaid diagrams (5 concept + 10 current-state)
- `docs/diagrams/database-schema.md` -- 4 ERD diagrams
- 29 old plan docs archived to `docs/plans/archive/`

### Build
- `mix compile --force`: 0 new warnings, 0 errors

### Next: Architecture-Informed Code Review
Use the documented understanding (spawn insight, signals backbone, Workshop ownership, Discovery readiness) as the lens for a targeted code review. Find code that contradicts these principles and make it actionable.
