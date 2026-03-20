# ICHOR IV - Handoff

## Current Status: Session 5 -- MES Team Launch Regression Fix (2026-03-20)

### What Was Done: Bugfix -- MES team not starting after unified Runner

**Root cause**: `Scheduler.spawn_run/0` calls `Runner.start(:mes, ...)` but never calls
`TeamLaunch.launch(spec)` to start the tmux team. DAG and Genesis both call
`TeamLaunch.launch(spec)` BEFORE starting their Runner. MES's `on_init` hook only registered
with the Janitor — it did NOT launch the team. The launch call was missing entirely.

**Fix**: `Hooks.MES.on_init/1` now builds the spec via `TeamSpecBuilder.build_team_spec/2`
and calls `team_launch().launch(spec)` before calling `Janitor.monitor_run/2`. Errors are
emitted as `:mes_cycle_failed` signals.

**File changed**: `lib/ichor/projects/runner/hooks/mes.ex`

**Build**: `mix compile --warnings-as-errors` EXIT:0

---

## Previous: Session 5 -- Phase 2 Simplification Steps 4-5 (2026-03-20)

### What Was Done: Phase 2 Steps 4-5 (Message Bus)

**Step 4: Created `lib/ichor/messages/bus.ex`** (`Ichor.Messages.Bus`)
- Replaces `Ichor.MessageRouter` as single delivery authority
- `resolve_target/1` promoted to public `resolve/1` (tagged tuples)
- API: `send/1`, `recent_messages/1`, `start_message_log/0`, `resolve/1`

**Step 5: Repointed 10 callers to `Bus`**
- `application.ex`, `agent_watchdog.ex`, `control/agent.ex`, `quality_gate.ex`
- `tools/archon/messages.ex`, `tools/agent/inbox.ex`
- `dashboard_messaging_handlers.ex`, `dashboard_dag_handlers.ex`
- `dashboard_session_control_handlers.ex`, `dashboard_state.ex`
- Trashed: `lib/ichor/message_router.ex` → `tmp/trash/`

**Build**: `mix compile --warnings-as-errors` EXIT:0, `mix credo --strict` EXIT:0

**Steps 1-3 (Events.Runtime)** not yet present -- parallel agent hadn't created it yet.
Bus was built independently as instructed.

### What Remains (Steps 6-8)
- Step 6: `event_bridge.ex` (do NOT touch yet)
- Step 7: `protocol_tracker.ex` (do NOT touch yet)
- Step 8: Full `gateway/router.ex` consolidation (do NOT touch yet)

---

## Previous: Session 5 -- Projects Domain Simplification Phase 1 (2026-03-20)

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
