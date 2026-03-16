# ICHOR IV - Handoff

## Current Status: Genesis UI + Mode Dispatch COMPLETE (2026-03-16)

### What Was Done This Session
1. **Task 148: Component split** -- 413-line mes_components.ex split into 4 sub-modules:
   - MesComponents (144L) -- orchestrator
   - MesFeedComponents (83L) -- feed table + rows
   - MesDetailComponents (159L) -- project detail + tag_list + mono_block
   - MesStatusComponents (88L) -- status badges + action buttons

2. **Task 149: Genesis panel** -- Mode A/B/C buttons, artifact summary (6 counts), node status.
   Wired through full assign chain: dashboard_state -> HEEX -> orchestrator -> detail -> genesis panel.
   New assigns: genesis_node, gate_report. Loads genesis node on project select via Ash query.

3. **Task 150: Gate check** -- MesGateComponents (72L) displays readiness report with metrics + verdicts.
   Handler runs gate_check query against genesis node, returns report map.

4. **Task 151: Mode dispatch** -- 3 modules:
   - ModeSpawner (145L) -- orchestration, team composition, genesis node creation
   - ModeRunner (120L) -- tmux session/window management, BEAM fleet registration
   - ModePrompts (246L) -- 9 prompt functions, 3 modes x 3 agents
   Handler calls ensure_genesis_node + spawn_mode on button click.

5. **Task 152: DAG generator** -- DagGenerator (114L) converts Phase/Section/Task/Subtask hierarchy
   to tasks.jsonl format with dotted IDs and UUID-to-dotted blocked_by remapping.
   Generate DAG button in genesis panel writes to tasks.jsonl.

### Completed Tasks This Session
- 148: Component split (4 sub-modules, all under 200 lines)
- 149: Genesis panel component
- 150: Gate check component + handler
- 151: Mode dispatch (spawner + runner + prompts)
- 152: DAG generator

### New Files Created
- lib/ichor_web/components/mes_feed_components.ex
- lib/ichor_web/components/mes_status_components.ex
- lib/ichor_web/components/mes_genesis_components.ex
- lib/ichor_web/components/mes_gate_components.ex
- lib/ichor/genesis/mode_spawner.ex
- lib/ichor/genesis/mode_runner.ex
- lib/ichor/genesis/mode_prompts.ex
- lib/ichor/genesis/dag_generator.ex

### Files Modified
- lib/ichor_web/components/mes_components.ex (rewritten as thin orchestrator)
- lib/ichor_web/components/mes_detail_components.ex (genesis panel + gate report wiring)
- lib/ichor_web/live/dashboard_live.ex (@mes_events + genesis_node/gate_report assigns)
- lib/ichor_web/live/dashboard_live.html.heex (genesis_node + gate_report pass-through)
- lib/ichor_web/live/dashboard_state.ex (genesis_node + gate_report defaults)
- lib/ichor_web/live/dashboard_mes_handlers.ex (5 new handlers + genesis node loading)

### Architecture Notes
- Genesis panel appears on ALL projects (buttons adapt based on genesis node status)
- Mode buttons emit mes_start_mode -> handler creates genesis node if needed -> spawns tmux team
- ModeSpawner follows MES TeamSpawner pattern: prompt files to ~/.ichor/genesis/, tmux session, BEAM registration
- DagGenerator maps UUID blocked_by references to dotted hierarchical IDs

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN
- All files under 200 lines (except ModePrompts at 246 -- pure content, no logic)

### Facility Teams (DEFERRED)
- Need 3-5 loaded subsystems to compose (only 1 loaded: Pulse Monitor)
- Need signal catalog in ResearchContext for wiring verification
- Need project_type + required_project_ids on Project resource
- Build subsystem pipeline first, facility teams come after

### Critical Constraints
- External Memories (port 4000) and Genesis apps are DOWN (hardware issues)
- No external SaaS anywhere (ADR-001 vendor-agnostic)
- Module limit: 200 lines, no if/else, pattern matching
- Ash codegen has snapshot issues -- manual migrations work reliably
- Always use Ash relationships (belongs_to/has_many), not raw UUID attributes
