# ICHOR IV - Handoff

## Current Status: Session 5 Complete (2026-03-20)

### Summary
Project orchestration collapsed from 6 modules to 2: `Spawn` + `TeamSpec`.
Compile clean, credo clean, server starts.

### What Was Done (Session 5)
1. **Created `lib/ichor/projects/team_spec.ex`** -- unified spec builder replacing `TeamSpecBuilder`, `DagTeamSpecBuilder`, `GenesisTeamSpecBuilder`. API: `build(:mes, run_id, team_name)`, `build(:dag, ...)`, `build(:genesis, ...)`, `build_corrective/4`, `session_name/1`, `prompt_dir/2-3`, `prompt_root_dir/1`.
2. **Created `lib/ichor/projects/spawn.ex`** -- unified spawner replacing `Spawner`, `ModeSpawner`, and inlining `TeamCleanup`. API: `spawn(:dag, node_id, project_id)`, `spawn(:genesis, mode, project_id, node_id)`, `ensure_genesis_node/2`, `load_project_brief/1`, `kill_session/1`, `cleanup_orphaned_teams/0`.
3. **Updated callers**: `runner.ex`, `dashboard_mes_handlers.ex`, `project_execution.ex`, `janitor.ex`
4. **Moved 6 old modules to tmp/trash/**: spawner, mode_spawner, team_spec_builder, dag_team_spec_builder, genesis_team_spec_builder, team_cleanup
5. **Fixed pre-existing**: event_bridge.ex unused `DLHelpers` alias (inlined into DecisionLog in prior session)

### Build
- `mix compile --warnings-as-errors` CLEAN
- `mix credo --strict` 0 new issues
- Server starts on port 4005

### Key Design
- `TeamSpec.build/N` dispatches on first arg atom (:mes/:dag/:genesis)
- `Spawn.spawn/3-4` dispatches on first arg atom (:dag/:genesis)
- All cleanup (formerly TeamCleanup) lives in Spawn
- Runner still uses configurable modules: `:mes_team_spec_builder_module` (default: TeamSpec), `:mes_team_cleanup_module` (default: Spawn)

### Next Steps (toward 60-file target)
**Level 3:** Domain model further consolidation:
- 4 workshop blueprint resources → 1 embedded blueprint model
- More GenServer → plain ETS/function demotions
- Continue inline pass: any remaining single-caller modules
