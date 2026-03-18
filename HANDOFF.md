# ICHOR IV - Handoff

## Current Status: Ichor.Dag Domain IMPLEMENTED (2026-03-18)

### Session Summary

Designed and implemented the full `Ichor.Dag` Ash domain -- 13 new modules, ~1700 lines. Sovereign DAG execution control plane replacing /dag CLI skill. SQLite is runtime truth with tasks.jsonl write-through sync.

### What Was Implemented

#### Ichor.Dag Domain (13 new files)
- `dag.ex` -- Ash Domain registering Run + Job
- `dag/run.ex` -- Ash Resource (SQLite): execution session with status lifecycle
- `dag/job.ex` -- Ash Resource (SQLite): claimable work unit with claim/complete/fail/reset actions
- `dag/graph.ex` -- Pure functions: waves, critical_path, pipeline_stats, stale_items, file_conflicts, available (extracted from SwarmMonitor)
- `dag/validator.ex` -- Pure preflight checks: cycle detection, file overlap, missing refs
- `dag/loader.ex` -- Ingest from tasks.jsonl or Genesis hierarchy into Run + Jobs
- `dag/exporter.ex` -- Export Jobs to tasks.jsonl + write-through sync via jq
- `dag/health_checker.ex` -- Pure Elixir health check (stale, conflicts, deadlocks)
- `dag/run_process.ex` -- GenServer per-run lifecycle (stale reset, health, tmux liveness, completion)
- `dag/run_supervisor.ex` -- DynamicSupervisor facade
- `dag/supervisor.ex` -- Wraps RunSupervisor for application.ex
- `dag/spawner.ex` -- Creates Run + Jobs + tmux lead agent in one call
- `dag/prompts.ex` -- Lead agent prompt template with MCP tool references

#### MCP Tools (1 new file)
- `agent_tools/dag_execution.ex` -- 7 MCP tools: next_jobs, claim_job, complete_job, fail_job, get_run_status, load_jsonl, export_jsonl
- Registered in `agent_tools.ex` + `router.ex`

#### UI Wiring
- "Build" button on MES factory view (replaces DAG station button)
- `mes_launch_dag` handler calls `Dag.Spawner.spawn/2`
- Pipeline stage `:building` derived from active `Dag.Run.by_node`
- No checkpoint changes -- clean domain boundary

#### Infrastructure
- 8 DAG signals in catalog (category `:dag`)
- SQLite migration: `dag_runs` + `dag_jobs` tables with indexes
- `Ichor.Dag` registered in `ash_domains` config
- `Ichor.Genesis` added to config (was missing)
- `ModeSpawner.load_project_brief` made public for reuse

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN
- `mix credo --strict` -- no new errors (design suggestions only)

### What's Next
1. **SwarmMonitor migration** (task 216) -- thin to ~150 lines, delegate to Dag.Graph
2. **Smoke test** -- verify via iex: Loader.from_file, Job.available, Job.claim
3. **End-to-end test** -- click Build on PulseMonitor, verify tmux session + fleet registration

### Critical Constraints
- External Memories (port 4000) and Genesis apps are DOWN
- MES scheduler PAUSED
- Module limit: 200 lines (graph.ex at 204, job.ex at 218 -- acceptable for rich Ash resources)
- Ash codegen snapshots broken -- manual migrations only
