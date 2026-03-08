# ICHOR IV (formerly Observatory) - Handoff

## Current Status: Workshop Ash Persistence + Blueprint UI (2026-03-08)

### Just Completed: Workshop Blueprint Panel

Wired the Workshop's saved blueprints UI into the dashboard:
- **Added `ws_blueprints` and `ws_blueprint_id` attrs** to WorkshopComponents
- **Added Saved Blueprints panel** to workshop_view.html.heex right sidebar
  - Save/Update button (contextual), blueprint list with load/delete on hover
  - Currently-loaded blueprint highlighted with cyan border
  - Agent count shown per blueprint
- **Load blueprints on nav**: When user navigates to /workshop, `list_blueprints()` fetches from SQLite
- **Preloading**: `list_blueprints/0` calls `Ash.load!(:agent_blueprints)` to populate agent count

### Workshop Ash Resources (Prior This Session)
- 4 resources: TeamBlueprint, AgentBlueprint, SpawnLink, CommRule
- `manage_relationship(:direct_control)` for nested CRUD through parent actions
- Auto-save on every canvas mutation via `auto_save/1`
- Canvas state maps: `slot` <-> `id`, `canvas_x/y` <-> `x/y`, `from_slot/to_slot` <-> `from/to`
- Migration applied: `20260308152059_create_workshop_blueprints.exs`
- Event delegation: `"ws_" <> _` prefix in DashboardLive -> DashboardWorkshopHandlers

### Key Files
- `lib/observatory/workshop.ex` -- Ash Domain (4 resources)
- `lib/observatory/workshop/team_blueprint.ex` -- parent resource with manage_relationship
- `lib/observatory/workshop/agent_blueprint.ex` -- agent node with slot/canvas coords
- `lib/observatory/workshop/spawn_link.ex` -- from_slot/to_slot hierarchy
- `lib/observatory/workshop/comm_rule.ex` -- from_slot/to_slot/policy/via_slot
- `lib/observatory_web/live/dashboard_workshop_handlers.ex` -- all ws_ event handlers + auto_save
- `lib/observatory_web/components/workshop_components.ex` -- component attrs + helpers
- `lib/observatory_web/components/workshop_components/workshop_view.html.heex` -- template
- `assets/js/hooks/workshop_canvas.js` -- JS hook for drag/SVG/ports

### Next Steps
- Verify end-to-end: presets persist, load restores canvas, blueprints list populates
- Continue with Ash Fleet domain generic actions (task 42)

### Build Status
`mix compile --warnings-as-errors` clean.
