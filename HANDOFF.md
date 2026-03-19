# ICHOR IV - Handoff

## Current Status: Session 3 -- Consolidation + Safety (2026-03-19)

### Session Summary

Coordinator-driven session. Codex (GPT-5.4) consulted as equal architectural partner. All implementation delegated to ash-elixir-expert agents. Build/credo/dialyzer delegated to agents to protect context window.

### What Was Done This Session

1. **Ground rules established** -- CLAUDE.md updated with coordinator operating model, agent routing table, codex invocation patterns, elixir skills requirement
2. **State document audit** -- codex verified progress.txt, BRAIN.md, HANDOFF.md against codebase. Found 9 stale claims.
3. **Consolidation plan** -- 6-phase plan written, codex-reviewed twice (14+6 findings incorporated):
   - Phase 0: Fix stale document claims
   - Phase 1: Quick wins (dead notifier, unsafe atoms, EventBuffer dedup, team.ex, termination)
   - Phase 2: Spawn convergence (all teams through Workshop presets + TeamLaunch)
   - Phase 3: Runner helper extraction (use macro, not behaviour)
   - Phase 4: Registry cleanup (scoped: stale deps + helper extraction)
   - Phase 5: Safety sweep (impure formatter, validate_config, async write-through)
   - Phase 6: Domain wrapper removal (Ash define)
4. **Nested module extraction** -- 11 modules extracted from 3 parent files into own files. Build clean.
5. **Oban candidate audit** -- 5 strong candidates (webhook_router, cron_scheduler, quality_gate, memories ingest, janitor), 5 maybe candidates. 2 bugs found (Task.start wrapping synchronous Signals.emit).
6. **RunnerRegistry extracted** -- Duplicated `via/1`, `lookup/1`, `list_all/0` across BuildRunner, PlanRunner, RunProcess extracted into `Ichor.Projects.RunnerRegistry`. All three runners updated. Build + credo clean.

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN
- `mix credo --strict` -- 2 pre-existing issues in mode_spawner.ex (out of scope, not touched)
- Git: clean on main

### Active Plan
- `~/.claude/plans/tender-giggling-nebula.md` -- approved, Phase 1 next

### Key Architectural Decisions
- All teams are equal. Workshop is the single authority for team topology.
- Workshop owns topology. Prompt content is flow-specific (prompt_builder function).
- Behaviour is wrong for runner consolidation. Use shared helper/macro instead.
- Codex is an equal partner, not a validator. Give it raw data, let it form conclusions.
- Oban installation planned for background job processing.
- RunnerRegistry is the canonical registry boilerplate helper for all runner GenServers.

### Key Files
- `~/.claude/plans/tender-giggling-nebula.md` -- session 3 plan (codex-reviewed)
- docs/plans/audit-*.md -- 4 deep audit reports (still relevant)
- docs/plans/INDEX.md -- all plans indexed
- `lib/ichor/projects/runner_registry.ex` -- NEW: shared registry helpers for runners
