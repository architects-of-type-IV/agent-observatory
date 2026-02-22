# Observatory - Handoff

## Current Status: Phase 2 DAG Ready + Skill Enforcement (2026-02-22)

### Just Completed

**Phase-to-DAG Script Improvements**
- Fixed jq template: hardcoded `done_when` now uses computed `$DONE_WHEN` variable (line 648)
- All 4 phases validated with `--dry-run` (phases 2-5)
- Generated Phase 2 tasks.jsonl: 5 sequential tasks for Gateway Core

**Skill Enforcement Mechanism**
- Created `~/.claude/rules/rule-always-phase-to-dag.md` (alwaysApply: true)
- Created `~/.claude/hooks/enforce-skill/phase-to-dag-gate.sh` (PreToolUse hook)
- Wired hook into `~/.claude/settings.json` as Bash matcher
- Pattern: hook blocks direct `phase-to-dag.sh` bash calls; skill-invoked calls use `PHASE_TO_DAG_SKILL=1` bypass token
- Tested: direct call blocked, skill-invoked call allowed

### Phase 2 Pipeline Ready
- `tasks.jsonl` has 5 tasks (sequential chain):
  1. SchemaInterceptor Module & Validation Contract (2.1)
  2. HTTP Endpoint & 422 Rejection (2.2)
  3. SchemaViolationEvent & Security (2.3)
  4. Topology Node State & Post-Validation Routing (2.4)
  5. Final migration + test suite
- Specs: `SPECS/implementation/2-gateway-core.md`, ADR-014, FRD-006
- Run `/dag run` from a fresh iTerm2 tab to execute

### Key Files Changed
| File | Change |
|------|--------|
| `~/.claude/skills/phase-to-dag/phase-to-dag.sh` | Fixed `$DONE_WHEN` in jq template (line 648) |
| `~/.claude/rules/rule-always-phase-to-dag.md` | NEW: always-on rule enforcing skill invocation |
| `~/.claude/hooks/enforce-skill/phase-to-dag-gate.sh` | NEW: PreToolUse hook blocking direct bash calls |
| `~/.claude/settings.json` | Added Bash PreToolUse hook for skill enforcement |
| `tasks.jsonl` | Phase 2 DAG: 5 tasks, sequential chain |

### Previous Milestones
- Phase 1: DecisionLog Schema (commit 2a10e77) -- 4 tasks, all complete
- Mode C Pipeline: 7 FRDs -> 5 phases, 24 sections, 77 tasks, 225 subtasks
- Mode B Pipeline: 12 ADRs -> 6 FRDs -> 79 UCs
- Swarm Control Center: all views complete, zero warnings

### Remaining
- [ ] Execute Phase 2 via `/dag run`
- [ ] Visual verification: all views
- [ ] Test feed with active agents spawning subagents
- [ ] Test DAG rendering with real pipeline running
- [ ] Remove dead ToolExecutionBlock module + delegate

## Architecture Reminders

- Phoenix LiveView on port 4005
- Event-driven: hooks -> POST /api/events -> Ash.create + PubSub -> LiveView
- Zero warnings: `mix compile --warnings-as-errors`
- Module size limit: 200-300 lines max
- embed_templates pattern: .ex (logic) + .heex (templates)
