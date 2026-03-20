# ICHOR IV - Handoff

## Current Status: Session 5 -- Projects Domain Simplification Phase 1 (2026-03-20)

### What Was Done This Session

Phase 1 simplification: deleted 5 trivial wrapper modules in the Projects domain (TeamCleanup kept).

**Modules trashed (moved to tmp/trash/):**
- `PlanSupervisor` -- single-child DynamicSupervisor wrapper. Now `{DynamicSupervisor, name: Ichor.Projects.PlanRunSupervisor, ...}` directly in `application.ex`
- `ExecutionSupervisor` -- same pattern. Now `{DynamicSupervisor, name: Ichor.Projects.DynRunSupervisor, ...}` directly in `application.ex`
- `RunSupervisor` -- facade over `DynRunSupervisor`. `DynamicSupervisor.start_child` inlined directly in `spawner.ex`
- `RunnerRegistry` -- convenience rename over Registry calls. `Registry.lookup/select` + via-tuple inlined into `BuildRunner`, `PlanRunner`, `RunProcess`
- `TeamLifecycle` -- thin orchestration wrapper around `TeamCleanup`. Spawn logic moved into `BuildRunner` directly, with config injection preserved (`:mes_team_spec_builder_module`, `:mes_team_launch_module`, `:mes_team_cleanup_module`)

**TeamCleanup kept** -- it has real implementation: signal emissions, file cleanup, orphan detection. `Janitor` and `Ichor.Tools.Archon.Mes` now call `TeamCleanup` directly (one fewer indirection hop).

### Files Changed
- `lib/ichor/application.ex` -- removed PlanSupervisor + ExecutionSupervisor, DynamicSupervisors inline
- `lib/ichor/projects/spawner.ex` -- RunSupervisor.start_run → DynamicSupervisor.start_child inline
- `lib/ichor/projects/plan_runner.ex` -- RunnerRegistry calls → Registry inline
- `lib/ichor/projects/run_process.ex` -- RunnerRegistry calls → Registry inline
- `lib/ichor/projects/build_runner.ex` -- RunnerRegistry + TeamLifecycle inlined, 3 config helpers added
- `lib/ichor/projects/janitor.ex` -- TeamLifecycle → TeamCleanup direct
- `lib/ichor/tools/archon/mes.ex` -- TeamLifecycle → TeamCleanup direct
- `lib/ichor/projects/scheduler.ex` -- stale comment updated

### Build Status
- `mix compile --warnings-as-errors`: EXIT 0 (322 files)
- `mix credo --strict`: 0 issues

### Next Steps
Continue with additional simplification passes as directed.
