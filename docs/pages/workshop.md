# Workshop Page

## Overview

The Workshop page is the team authoring surface. It is rendered inside
`DashboardLive` when `?view=workshop` and is backed by the `Ichor.Workshop`
domain.

Current backend truth:

- `Team` = saved Workshop team definition
- `TeamMember` = persisted member definition for a team
- `AgentType` = reusable archetype
- `CanvasState` = pure editor state transitions
- `ActiveTeam` / `Agent` = runtime read surfaces

The UI may still say `blueprint` in some copy, but the backend and persisted
resource names are now `Team`.

## Layout

The page is split into:

- left: canvas plus preset/toolbar controls
- right: stacked management sidebar

The canvas is rendered by the `WorkshopCanvas` hook and is intentionally
`phx-update="ignore"`.

## Presets

Preset buttons come from `Ichor.Workshop.Presets.ui_list/0`.

Current built-in presets include:

- `pipeline`
- `solo`
- `research`
- `review`
- `mes`
- planning presets used by Factory-generated teams

Applying a preset fires `ws_preset`. The handler:

- clears current canvas state
- applies the preset through `CanvasState` / `Presets`
- auto-saves the resulting team state

## Canvas

The canvas is a visual editor for:

- agents
- spawn links
- communication rules

The hook renders:

- draggable agent nodes
- green spawn ports
- cyan comm-rule ports
- SVG connection lines

Server-side state is kept in `ws_*` assigns, including:

- `ws_agents`
- `ws_spawn_links`
- `ws_comm_rules`
- `ws_selected_agent`
- `ws_team_name`
- `ws_strategy`
- `ws_default_model`
- `ws_cwd`
- `ws_team_id`

The pure state transitions live in
[/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/canvas_state.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/canvas_state.ex).

## Agent Editing

Workshop supports:

- `ws_add_agent`
- `ws_add_agent_from_type`
- `ws_select_agent`
- `ws_move_agent`
- `ws_update_agent`
- `ws_remove_agent`
- `ws_add_spawn_link`
- `ws_remove_spawn_link`
- `ws_add_comm_rule`
- `ws_remove_comm_rule`
- `ws_update_team`

These are handled by
[/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_workshop_handlers.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_workshop_handlers.ex).

## Persistence

Workshop persistence is handled by
[/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/workshop_persistence.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/workshop_persistence.ex).

Current persistence events are:

- `ws_save_team`
- `ws_load_team`
- `ws_delete_team`
- `ws_new_team`
- `ws_list_teams`

Auto-save writes through `Ichor.Workshop.Team` and then syncs members through
`Ichor.Workshop.TeamMember.sync_from_workshop_state/2`.

The saved-team list now comes from `Team.list_all!/0`, not a blueprint resource.

## Agent Types

Agent archetypes are managed through `Ichor.Workshop.AgentType`.

Current type events are:

- `ws_edit_type`
- `ws_edit_type_new`
- `ws_cancel_edit_type`
- `ws_save_type`
- `ws_delete_type`

These are handled by
[/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/workshop_types.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/workshop_types.ex).

Agent types are used both by the Workshop UI and by presets to stamp out
initial team members.

## Launching Teams

The launch button fires `ws_launch_team`.

The current launch path is:

1. auto-save current Workshop state
2. load the saved `Team`
3. sync `TeamMember` records from the current canvas state
4. call `Team.spawn_team(team.name)`

That means the launch surface is now tied to the persisted `Workshop.Team`
resource, not to the old direct blueprint builder path.

The generic runtime team shape remains
[/Users/xander/code/www/kardashev/observatory/lib/ichor/infrastructure/team_spec.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/infrastructure/team_spec.ex).
`Workshop.TeamSpec` is currently a builder used by Factory-generated run modes,
and should be revisited when Workshop’s next redesign lands.

## Runtime Views

Workshop also owns the runtime-facing read surfaces used by the dashboard:

- `Ichor.Workshop.Agent`
- `Ichor.Workshop.ActiveTeam`

These are not the persisted authoring records. They are live projections loaded
from the running system for `/fleet` and related views.

## Key Files

- [/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/team.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/team.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/team_member.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/team_member.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/agent_type.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/agent_type.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/canvas_state.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/canvas_state.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/presets.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/presets.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_workshop_handlers.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_workshop_handlers.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/workshop_persistence.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/workshop_persistence.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/workshop_types.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/workshop_types.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/workshop_components/workshop_view.html.heex](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/workshop_components/workshop_view.html.heex)
