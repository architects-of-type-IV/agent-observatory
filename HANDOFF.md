# ICHOR IV - Handoff

## Current Status: W2 Fixes In Progress, Wave 3 Next (2026-03-21)

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
- W1-1 through W1-7 done

**Wave 2 (Oban Migration)** -- COMPLETE, Codex 6/10 -> fixes in progress
- W2-1/W2-2/W2-3: 3 GenServers replaced with Oban workers + plain APIs
- W2-fix-1: Engine set to Oban.Engines.Lite (DONE)
- W2-fix-2: Worker idempotency fixes (DONE, agents completed)
- W2-fix-3: Crash window closed in webhook_adapter + cron_scheduler (DONE, agents completed)
- W2-fix-4: Uniqueness on recover_jobs (DONE, agents completed)
- Codex re-review dispatched, waiting for response

**Wave 3 (Structural)** -- NEXT
- W3-1: EventStream decouple from fleet mutations (X1/Problem 2)
- W3-2: TeamSpec strategy injection via compile/2 (AD-6)
- W3-3: RunSpec + AgentId value objects (A1+A2)
- W3-4: TeamWatchdog -> Oban cleanup jobs (X2/O3/AD-8 closure)

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
- Verify build after agents complete, resolve conflicts

### Build
- `mix compile --warnings-as-errors`: CLEAN
