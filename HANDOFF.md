# ICHOR IV - Handoff

## Current Status: Genesis Mode A E2E + MES UI Redesign In Progress (2026-03-17)

### What Was Done This Session

#### Genesis Mode A End-to-End Smoke Test
1. **Phase 1: Component verification** -- MCP tools (create_adr, list_adrs, gate_check), script generation, tmux + fleet registration all verified working.
2. **Bug fixes found during verification:**
   - Scout `--allowedTools` was blocking MCP messaging tools (check_inbox, send_message). Fixed in TmuxHelpers.
   - Reviewer prompt was missing `AVAILABLE MCP TOOLS` section. Fixed in ModePrompts.
3. **Phase 2: Full pipeline fire** -- Mode A launched on PulseMonitor. 3 agents spawned (coordinator, architect, reviewer). All communicated via MCP. 3 ADRs persisted in DB, gate check passed.
4. **Protocol violation found:** Coordinator self-synthesized ADRs at 3 minutes instead of waiting for architect/reviewer. Root cause: prompt said "If architect stalls after 5 minutes, synthesize ADRs yourself."

#### Prompt Fixes (All 3 Modes)
- Removed self-synthesis escape clauses from all coordinator prompts
- Added explicit patience rules: "You MUST wait", "NEVER create artifacts yourself"
- Added protocol enforcement: "If you break protocol, the team will be destroyed"
- Sequential WAIT steps with time allowances (8min workers, 3-5min reviewers)

#### Genesis RunProcess (Team Lifecycle)
- Created `Genesis.RunProcess` -- GenServer mirroring MES RunProcess pattern
- Subscribes to `:messages`, detects coordinator -> operator delivery
- Liveness polls tmux session (30s). On completion: kills tmux, disbands fleet, cleans prompt files
- Created `Genesis.Supervisor` with `RunSupervisor` DynamicSupervisor
- Wired into `ModeSpawner.spawn_mode` and `application.ex`
- Added `ModeRunner.kill_session/3` for cleanup

#### MES Scheduler Fix
- Pause flag moved from `~/.ichor/mes/paused` to `tmp/mes_paused` (project-local, survives restarts)
- MES scheduler was auto-starting on server restart because the global flag was missing

#### PulseMonitor Status Reset
- Reset from `loaded` to `proposed` (it was never actually built)

#### MES UI Redesign (IN PROGRESS -- design phase)
- Built playground (`tmp/mes-dashboard-playground.html`) to explore layouts
- Multiple iterations: panels -> integrated sections -> reader sidebar -> factory pipeline
- **Key insight: MES is an automated factory, not a project browser**
- Design decisions saved to `memory/project_mes_ui_decisions.md`
- Factory state machine vision saved to `memory/project_factory_state_machine.md`
- Current GenesisTabComponents exists but needs rewrite based on new unified view design
- Design doc at `docs/plans/2026-03-17-mes-unified-design.md` needs rewrite with factory pipeline framing

### What's Next
1. **Rewrite MES UI design** -- spawn architect agents to design the unified factory pipeline view. The design doc exists but doesn't reflect the state machine insight.
2. **Re-test Mode A** -- prompts are fixed, RunProcess is wired. Need to launch again and verify coordinator follows protocol. Server needs restart to pick up all changes.
3. **State machine mapping** -- resolve the gap between MES Project status (proposed/loaded) and pipeline reality (ideation/discover/define/build/dag/executing/compiled/loaded)

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN
- `mix credo --strict` on changed files -- No issues

### New Files Created
- lib/ichor/genesis/run_process.ex
- lib/ichor/genesis/supervisor.ex
- lib/ichor_web/components/genesis_tab_components.ex (exists but needs rewrite)
- docs/plans/2026-03-17-genesis-mode-a-smoketest.md
- docs/plans/2026-03-17-genesis-tab-design.md (superseded)
- docs/plans/2026-03-17-genesis-tab-plan.md (superseded)
- docs/plans/2026-03-17-mes-unified-design.md (needs rewrite with pipeline framing)
- tmp/mes-dashboard-playground.html

### Files Modified
- lib/ichor/fleet/tmux_helpers.ex (scout allowedTools + MCP messaging)
- lib/ichor/genesis/mode_prompts.ex (patience rules, protocol enforcement)
- lib/ichor/genesis/mode_runner.ex (kill_session, cleanup_prompt_files)
- lib/ichor/genesis/mode_spawner.ex (start_run_process after team creation)
- lib/ichor/application.ex (Genesis.Supervisor added)
- lib/ichor/mes/scheduler.ex (pause flag path to tmp/mes_paused)
- lib/ichor_web/components/mes_components.ex (Planning tab, genesis_nodes attr)
- lib/ichor_web/components/mes_detail_components.ex (removed genesis panel)
- lib/ichor_web/live/dashboard_mes_handlers.ex (genesis events, safe atom mapping)
- lib/ichor_web/live/dashboard_state.ex (genesis assigns)
- lib/ichor_web/live/dashboard_live.ex (genesis events list)
- lib/ichor_web/live/dashboard_live.html.heex (genesis assigns passthrough)
- assets/css/app.css (genesis-prose CSS)

### Critical Constraints
- External Memories (port 4000) and Genesis apps are DOWN (hardware issues)
- MES scheduler is PAUSED (tmp/mes_paused flag set)
- All genesis test data was cleaned (nodes, ADRs, checkpoints deleted)
- No external SaaS anywhere (ADR-001 vendor-agnostic)
- Module limit: 200 lines, no if/else, pattern matching
