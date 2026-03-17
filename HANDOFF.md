# ICHOR IV - Handoff

## Current Status: Ichor.Dag Domain Planned + Tasks Written (2026-03-18)

### Session Summary

Made DagGenerator /dag-compatible (Phase 1), then designed the full `Ichor.Dag` Ash domain through extensive planning with 4 reviewer agents (code reviewer, naming reviewer, codex, ash expert). Plan approved and 19 tasks written to tasks.jsonl (IDs 200-218).

### What Was Done This Session

#### DagGenerator /dag Compatibility (completed)
- Added missing fields: `priority`, `acceptance_criteria`, `updated`, `notes`, `roadmap_ref`
- Fixed ISO 8601 timestamps (was date-only)
- Handler fix: `File.write!` -> `[:append]` mode
- Dead code cleanup: moved `genesis_tab_components.ex` and `mes_research_components.ex` to trash

#### Ichor.Dag Domain Design (planned, not yet implemented)
- Comprehensive plan at `~/.claude/plans/tender-giggling-nebula.md`
- 4 reviewer passes: naming, code review, codex, ash expert
- 19 tasks in tasks.jsonl (IDs 200-218), 8 phases
- Agent system prompt saved to `SPECS/dag/AGENT_PROMPT.md`

### Ichor.Dag Domain Architecture

New top-level Ash domain with 14 modules:
- **Resources**: `Dag.Run` (SQLite, execution session), `Dag.Job` (SQLite, claimable work unit)
- **Pure functions**: `Dag.Graph` (waves, critical path, stats -- extracted from SwarmMonitor), `Dag.Validator` (cycles, overlaps, preflight -- from phase-to-dag)
- **I/O**: `Dag.Loader` (tasks.jsonl + Genesis -> DB), `Dag.Exporter` (DB -> tasks.jsonl + write-through sync)
- **Lifecycle**: `Dag.HealthChecker`, `Dag.RunProcess`, `Dag.RunSupervisor`, `Dag.Supervisor`
- **Execution**: `Dag.Spawner`, `Dag.Prompts`
- **MCP**: `AgentTools.DagExecution` (7 tools: next_jobs, claim_job, complete_job, fail_job, get_run_status, load_jsonl, export_jsonl)

Key design decisions:
- SQLite is runtime truth, tasks.jsonl syncs via write-through (serialized through RunProcess)
- Pipeline stage `:building` derived from active Dag.Run, NOT from Genesis Checkpoint
- Job naming: `external_id` (not item_id), `allowed_files` (not files), `phase_label` (not feature), `:reset` (not heal), `tmux_session` (not session), `source: :imported` (not :external)
- Job.claim re-checks blocked_by transactionally
- Job.available uses two-query prepare (SQLite can't filter JSON arrays)

### What's Next

1. **Implement Ichor.Dag domain** -- 19 tasks across 8 phases in tasks.jsonl (IDs 200-218)
2. Start with Phase 1: Core Ash Resources (tasks 200-204)
3. Can be executed via DAG team or sequentially

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN

### Critical Constraints
- External Memories (port 4000) and Genesis apps are DOWN (hardware issues)
- MES scheduler is PAUSED (tmp/mes_paused flag set)
- No external SaaS
- Module limit: 200 lines, pattern matching, no if/else
- Ash codegen snapshots broken -- use manual migrations
- Agent system prompt: SPECS/dag/AGENT_PROMPT.md (shape-first, boundary-aware)
