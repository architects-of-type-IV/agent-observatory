# ICHOR IV (formerly Observatory) - Handoff

## Current Status: Workshop Refactor Complete (2026-03-08)

### Just Completed: Workshop Module Split + Idiomatic Polish

Split `dashboard_workshop_handlers.ex` (637 -> 198 lines) into 4 focused modules:

- **`dashboard_workshop_handlers.ex`** (198 lines) -- Canvas CRUD: agents, links, rules, team config, preset, launch
- **`workshop_persistence.ex`** (154 lines) -- Blueprint events, auto-save, Ash <-> canvas mapping, clear/load
- **`workshop_presets.ex`** (120 lines) -- Declarative `@presets` map (dag/solo/research/review), topological spawn_order
- **`workshop_types.ex`** (65 lines) -- AgentType CRUD events (edit/save/delete)

Also:
- `workshop.ex` domain: registered AgentType resource
- `agent_type.ex`: Ash resource with sorted!() code interface
- Migration for workshop_agent_types table
- DashboardLive routing: specific type/blueprint events first, `"ws_" <> _` catch-all last
- Removed placeholder "Add Comm Rule" buttons, replaced with drag hint text
- `dashboard_state.ex`: added `ws_blueprints` + `ws_agent_types` init assigns
- Cleaned up naming redundancies and junior-level code patterns

### Prior: Ash-Disciplined Refactor (Phases 1-7)

Net -730 lines from web layer. Domain logic moved into Fleet/Activity/Workshop modules.

### Remaining
- **Phase 8**: ICHOR IV rename (each rename own commit per plan)
- Tasks 38-40: Eliminate legacy ETS (CommandQueue, TeamWatcher, Mailbox)

### Build Status
`mix compile --warnings-as-errors` clean.
