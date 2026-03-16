# ICHOR IV - Handoff

## Current Status: Genesis Pipeline COMPLETE + Simplify Pass (2026-03-16)

### What Was Done This Session

#### Tasks 148-152: Genesis UI + Mode Dispatch + DAG Generator
1. **Task 148: Component split** -- 413-line mes_components.ex into 4 sub-modules (feed 83L, detail 159L, status 88L, orchestrator 144L)
2. **Task 149: Genesis panel** -- Mode A/B/C buttons, artifact summary (6 counts), node status. Wired through full assign chain.
3. **Task 150: Gate check** -- MesGateComponents (72L) with readiness metrics + verdicts. Handler runs gate_check query.
4. **Task 151: Mode dispatch** -- ModeSpawner (145L) + ModeRunner (90L) + ModePrompts (246L). Spawns tmux teams per mode.
5. **Task 152: DAG generator** -- DagGenerator (100L) converts Phase/Section/Task/Subtask hierarchy to tasks.jsonl.

#### Simplify / Quality Pass
- **N+1 fix**: DagGenerator now uses single `Ash.load(phases, [sections: [tasks: :subtasks]])` instead of 126+ cascading queries
- **TmuxHelpers extraction**: Shared `Ichor.Fleet.TmuxHelpers` module for 5 helpers duplicated across AgentSpawner, TeamSpawner, ModeRunner
- **Atom keys**: Gate report uses atom keys (not string keys) for idiomatic Elixir
- **Tailwind static classes**: Both `count_card_classes/1` and `tag_classes/1` use pattern-matched static strings
- **Single-query patterns**: `run_gate_check` and `load_genesis_node_by_id` each use one DB call instead of two
- **Credo clean**: No new issues. Dialyzer: 0 errors.

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN
- `mix credo --strict` -- No new issues (pre-existing only)
- `mix dialyzer` -- 0 errors

### New Files Created
- lib/ichor_web/components/mes_feed_components.ex
- lib/ichor_web/components/mes_status_components.ex
- lib/ichor_web/components/mes_genesis_components.ex
- lib/ichor_web/components/mes_gate_components.ex
- lib/ichor/genesis/mode_spawner.ex
- lib/ichor/genesis/mode_runner.ex
- lib/ichor/genesis/mode_prompts.ex
- lib/ichor/genesis/dag_generator.ex
- lib/ichor/fleet/tmux_helpers.ex

### What's Next
All Genesis pipeline tasks (140-152) are complete. Potential next steps:
- **Subsystem pipeline**: Build more subsystems to unblock Facility teams (need 3-5 loaded)
- **Signal catalog enrichment**: Add signal catalog to ResearchContext for wiring verification
- **MES Research tab refinement**: mes_research_components.ex is 296L (over limit, pre-existing)
- **TmuxHelpers migration**: Migrate AgentSpawner and TeamSpawner to use shared TmuxHelpers (reduces 3 copies to 1)
- **Genesis pipeline end-to-end test**: Run Mode A on a real project to validate prompts and MCP tool wiring

### Facility Teams (DEFERRED)
- Need 3-5 loaded subsystems to compose (only 1 loaded: Pulse Monitor)
- Need signal catalog in ResearchContext for wiring verification
- Need project_type + required_project_ids on Project resource

### Critical Constraints
- External Memories (port 4000) and Genesis apps are DOWN (hardware issues)
- No external SaaS anywhere (ADR-001 vendor-agnostic)
- Module limit: 200 lines, no if/else, pattern matching
- Ash codegen has snapshot issues -- manual migrations work reliably
