# ICHOR IV - Handoff

## Current Status: Ichor.Dag Domain -- Upfront Team Spawning (2026-03-18)

### Session Summary

Implemented full Ichor.Dag Ash domain (13 modules), then iteratively fixed spawning to match the proven MES TeamSpawner pattern. Three major rewrites: (1) AgentSpawner fixed to write .sh scripts like MES, (2) InstructionOverlay pollution removed, (3) ALL agents now spawned upfront -- no dynamic spawning.

### Architecture (FINAL)

**DAG team spawn follows MES TeamSpawner pattern exactly:**
1. Analyze job graph -> group by shared allowed_files -> determine worker count
2. Create ALL agent prompts (coordinator + lead + N workers) with full job specs
3. Write prompt .txt + .sh scripts via ModeRunner
4. tmux new-session (coordinator) + new-window (lead + workers) -- ALL at once
5. Register ALL agents in fleet with liveness_poll
6. Start RunProcess lifecycle monitor

**NO dynamic spawning. Workers exist from the start.** Lead dispatches to existing workers via send_message. Workers claim/complete their own jobs via MCP tools.

### Key Lessons Learned (Critical for Next Session)

1. **MES TeamSpawner is the gold standard.** Any new team spawning MUST follow this exact pattern: write prompt files -> .sh scripts -> tmux session/windows -> fleet registration. No exceptions.

2. **Never write to .claude/ directory.** Claude auto-reads all .md files in .claude/. InstructionOverlay wrote ICHOR_OVERLAY.md there, which poisoned ALL agents including Mode A Genesis teams. Overlays now go to ~/.ichor/agents/ or ~/.ichor/overlays/.

3. **No dynamic spawning via spawn_agent MCP tool.** It uses AgentSpawner which has a different (inferior) path than ModeRunner. Workers spawned dynamically don't appear in fleet, can't communicate via MCP. Spawn everything upfront.

4. **Archon TeamWatchdog is signal-driven.** Reacts to :dag_tmux_gone, :team_disbanded, :agent_stopped. No timers. Archives orphaned runs, resets jobs, notifies operator inbox.

5. **ash-elixir-expert.md is mandatory.** Every code change must be evaluated through shape-first, boundary-first lens. Pure functions separated from orchestration. Resources own entity rules. No exceptions.

### Files Created This Session

| File | Purpose |
|------|---------|
| `lib/ichor/dag.ex` | Ash Domain |
| `lib/ichor/dag/run.ex` | Ash Resource: execution session |
| `lib/ichor/dag/job.ex` | Ash Resource: claimable work unit |
| `lib/ichor/dag/graph.ex` | Pure functions: waves, critical path, stats |
| `lib/ichor/dag/validator.ex` | Pure preflight checks |
| `lib/ichor/dag/loader.ex` | Ingest from tasks.jsonl or Genesis |
| `lib/ichor/dag/exporter.ex` | Export + write-through sync |
| `lib/ichor/dag/health_checker.ex` | Pure Elixir health check |
| `lib/ichor/dag/run_process.ex` | GenServer lifecycle monitor |
| `lib/ichor/dag/run_supervisor.ex` | DynamicSupervisor facade |
| `lib/ichor/dag/supervisor.ex` | Wraps RunSupervisor |
| `lib/ichor/dag/spawner.ex` | Creates ALL agents upfront |
| `lib/ichor/dag/prompts.ex` | Coordinator + lead + worker prompts |
| `lib/ichor/dag/worker_groups.ex` | Pure job-to-worker grouping |
| `lib/ichor/agent_tools/dag_execution.ex` | 7 MCP tools |
| `lib/ichor/archon/team_watchdog.ex` | Signal-driven lifecycle monitor |
| `lib/ichor/archon/team_watchdog/reactions.ex` | Pure decision logic |

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN
- `mix dialyzer` -- CLEAN

### What's Next
1. Press Build on PulseMonitor and monitor the upfront-spawned team
2. SwarmMonitor migration (task 216) -- deferred
3. Verify workers appear in fleet and comms flow
