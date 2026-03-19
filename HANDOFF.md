# ICHOR IV - Handoff

## Current Status: Deep Audit + Physical Reorg Session (2026-03-19, session 2)

### Session Summary

Coordinator-driven session continuing from session 1. All work delegated to ash-elixir-expert agents. Codex consulted for every architectural decision.

### What Was Done This Session

1. **Physical file reorganization** -- 136 module renames across 4 batches (committed `34fe9ee`):
   - Batch 1: events/ + activity/ → observability/ (12 modules)
   - Batch 2: agent_tools/ + archon/tools/ → tools/agent/ + tools/archon/ (21 modules)
   - Batch 3: fleet/ + workshop/ → control/ (39 modules)
   - Batch 4: genesis/ + mes/ + dag/ → projects/ (64 modules)

2. **Simplification pass** -- dead code removal (-450 lines, committed `81fdbd3`):
   - 3 dead modules deleted (entry_formatter, stream_entry, broadcast)
   - 20+ unused functions removed across 23 files
   - 8 dead functions in fleet (spawn_agent_on, status, lookup_cluster, etc.)

3. **Test cleanup** -- 31 test files + 11 stubs moved to tmp/trash/

4. **Deep codebase audit** -- 4 audit reports covering all 214 files:
   - docs/plans/audit-control.md (40 files, 21 findings)
   - docs/plans/audit-projects.md (55 files, 10 priority items)
   - docs/plans/audit-observability-tools.md (35 files, 18 findings)
   - docs/plans/audit-infrastructure.md (65 files)

5. **Ash idioms reference** -- docs/plans/ash-idioms-reference.md (7 DSL patterns)

6. **XRef graph** -- docs/plans/xref-graph.txt (738 edges, 5 dependency cycles)

7. **MES team topology restored** -- prompts reverted to original working flow:
   - Lead is active dispatcher again (not passive rubber-stamp)
   - Researchers get assignments from Lead, report back to Lead
   - No peer review loop (was causing serial bottleneck)

8. **Bugs fixed**:
   - LiveView stream_configure crash on signals view navigation
   - MES spawn failure (cyclic spawn links → empty agents list)
   - Workshop presets now data-driven (loop, not hardcoded buttons)

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN
- `mix credo --strict` -- CLEAN (325 files, 0 issues)
- Server running on port 4005

### Uncommitted Changes
- team_prompts.ex -- MES topology restored
- presets.ex -- spawn links fixed, ui_list/0 added, MES preset updated
- dashboard_live.ex -- stream_configure guard fix
- workshop_view.html.heex -- preset buttons loop

### Critical Audit Findings (Next Session Priority)

1. **~100 domain wrapper functions** in control.ex and projects.ex -- should use Ash `define` on resources
2. **3 duplicate lifecycle GenServers** (BuildRunner, PlanRunner, RunProcess) -- 60 lines shared boilerplate each
3. **3 parallel spawn chains** (MES, Genesis, DAG) -- should converge to one Workshop-based path
4. **Dead FromAsh notifier** on virtual Observability.Task
5. **Signal side effect** in GenesisFormatter.to_map (impure function)
6. **2x unsafe String.to_existing_atom** in tool modules
7. **5 dependency cycles** (14-node control cycle is biggest)
8. **Triplicated EventBuffer reader** in 3 preparation modules

### Key Files
- docs/plans/INDEX.md -- all plans indexed with timestamps
- docs/plans/VALIDATION.md -- plan status validation (being generated)
- docs/plans/ash-idioms-reference.md -- correct Ash patterns
