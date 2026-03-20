# ICHOR IV - Handoff

## Current Status: Session 5 -- Phase 4 Tool Collapse + MES Fixes (2026-03-20)

### What Was Done: Phase 4 Tool Surface Collapse (21 modules → 6)

**New consolidated tool modules:**
- `RuntimeOps` -- 18 actions merged from 9 modules
- `AgentMemory` -- 10 actions merged from 4 modules
- `ProjectExecution` -- 14 actions merged from 3 modules
- `Genesis` -- 18 actions merged from 4 modules + formatter
- `ArchonMemory` -- stays as-is (already single file)
- 20 tool modules deleted, all tool names preserved

**MES duplicate briefs fix:**
- Planner prompt updated
- ResearchContext broadened
- ProjectIngestor guard added

**MES UI:**
- Sidebar wider (300px)
- Font sizes increased
- Subsystem list capped

**Build**: `mix compile --warnings-as-errors` EXIT:0, `mix credo --strict` 0 issues

---

## Previous: Session 5 -- MES Team Launch Regression Fix (2026-03-20)

### What Was Done: Bugfix -- MES team not starting after unified Runner

**Root cause**: `Scheduler.spawn_run/0` calls `Runner.start(:mes, ...)` but never calls
`TeamLaunch.launch(spec)` to start the tmux team. DAG and Genesis both call
`TeamLaunch.launch(spec)` BEFORE starting their Runner. MES's `on_init` hook only registered
with the Janitor -- it did NOT launch the team. The launch call was missing entirely.

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

### What Remains (Steps 6-8)
- Step 6: `event_bridge.ex` (do NOT touch yet)
- Step 7: `protocol_tracker.ex` (do NOT touch yet)
- Step 8: Full `gateway/router.ex` consolidation (do NOT touch yet)

---

## Previous: Session 5 -- Projects Domain Simplification Phase 1 (2026-03-20)

**Modules trashed:**
- `PlanSupervisor`, `ExecutionSupervisor` -- single-child DynamicSupervisor wrappers
- `RunSupervisor` -- facade over `DynRunSupervisor`
- `RunnerRegistry` -- convenience rename over Registry calls
- `TeamLifecycle` -- thin orchestration wrapper around `TeamCleanup`

**TeamCleanup kept** -- real logic: signal emissions, file cleanup, orphan detection.

### Build Status
- `mix compile --warnings-as-errors`: EXIT 0
- `mix credo --strict`: 0 issues
