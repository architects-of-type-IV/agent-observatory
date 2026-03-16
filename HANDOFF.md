# ICHOR IV - Handoff

## Current Status: Genesis Domain + MCP Tools COMPLETE (2026-03-16)

### What Was Done This Session
1. **MES prompt redesign** -- ResearchContext, boundary map, pain points, Factorio model
2. **SessionEviction** -- stale session purge from dashboard sidebar (10min TTL)
3. **DashboardInfoHandlers** -- :agent_stopped handler for sidebar refresh
4. **NudgeEscalator** -- nil session_id crash fix
5. **Scheduler** -- pause/resume with persistent file flag
6. **No-SaaS cleanup** -- removed all Slack/Telegram/PagerDuty references
7. **Genesis domain** (tasks 140-144) -- 10 Ash resources with proper belongs_to/has_many relationships
8. **MCP tools** (tasks 146-147) -- 20 tools across 4 modules (GenesisNodes, GenesisArtifacts, GenesisGates, GenesisRoadmap)
9. **Task 145** (MES Project FK) -- handled via Node.belongs_to :mes_project

### Completed Tasks This Session
- 140: Genesis domain + Node resource
- 141: ADR resource
- 142: Feature + UseCase resources
- 143: Checkpoint + Conversation resources
- 144: Phase/Section/Task/Subtask hierarchy
- 145: MES Project genesis_node_id FK (via belongs_to on Node)
- 146: MCP tools for Genesis artifact CRUD (15 tools)
- 147: MCP tools for Mode C roadmap (5 tools)

### Next Steps
1. Task 148: Component split -- extract MES sub-components (under 200 lines each)
2. Task 149: UI -- Genesis panel component (Mode A/B/C buttons, artifact summary)
3. Task 150: UI -- Gate check component + handler
4. Task 151: Mode dispatch -- team spawning + prompts for Mode A/B/C
5. Task 152: DAG generator -- Subtask hierarchy to tasks.jsonl

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
- Always architect solutions with agents before coding
- "Never think of solutions yourself. LLMs can judge and discuss."

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN
- All 10 Genesis resources tested with CRUD + relationship loading
- All 20 MCP tools tested via Ash.ActionInput + Ash.run_action
