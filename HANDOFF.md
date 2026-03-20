# ICHOR IV - Handoff

## Current Status: Session 7 Complete (2026-03-20)

### Summary
Level 2 domain consolidation: 4 workshop blueprint resources collapsed into 1 embedded Blueprint resource. 3 child tables eliminated.

### What Was Done (Session 7)
1. **Created `lib/ichor/control/blueprint.ex`** -- replaces TeamBlueprint. Agents, spawn_links, and comm_rules are `{:array, :map}` embedded JSON attributes instead of separate DB tables.
2. **Wrote migration `20260320150000_consolidate_blueprints.exs`** -- creates `workshop_blueprints`, migrates existing rows (JSON re-encoding), drops 4 old tables. Migration ran clean.
3. **Updated `lib/ichor/control/blueprint_state.ex`** -- `apply_blueprint/2` reads `blueprint.agents` (was `blueprint.agent_blueprints`). All conversion helpers use string keys (SQLite JSON loads with string keys).
4. **Updated `lib/ichor/control.ex`** -- 9 resources → 6. TeamBlueprint, AgentBlueprint, SpawnLink, CommRule removed.
5. **Updated callers**: `workshop_persistence.ex`, `dashboard_workshop_handlers.ex`, `team_spec.ex`, `workshop_view.html.heex` (bp.agents instead of bp.agent_blueprints).
6. **Moved 4 old files to tmp/trash/**: team_blueprint.ex, agent_blueprint.ex, comm_rule.ex, spawn_link.ex.

### Build
- `mix compile --warnings-as-errors` CLEAN
- `mix credo --strict` 0 issues
- `mix ecto.migrate` CLEAN
- Server boots (port conflict only -- app itself clean)

### Key Design Notes
- SQLite deserializes `{:array, :map}` JSON back with string keys -- never dot-access these maps
- Canvas state uses atom-key maps; `persisted_to_*` / `*_to_persisted` are the string/atom boundary
- `list_all` replaces `list_with_relationships` (no joins needed)

### Next Steps
- Simplification Phase 5: Memory store cleanup
- Oban worker migration (5 strong candidates)
- More GenServer → plain function demotions
