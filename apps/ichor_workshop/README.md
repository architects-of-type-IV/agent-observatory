# ichor_workshop

Ash Domain for designing, saving, and launching team blueprints from the Workshop canvas.

## Ash Domains

**`Ichor.Workshop`** -- owns five persisted resources backed by SQLite via `AshSqlite`.

| Resource | Description |
|---|---|
| `Ichor.Workshop.AgentType` | Reusable agent type definition (role, model, capabilities) |
| `Ichor.Workshop.TeamBlueprint` | Saved team composition with strategy, model, and working directory |
| `Ichor.Workshop.AgentBlueprint` | Agent slot within a team blueprint |
| `Ichor.Workshop.SpawnLink` | Directed dependency between two agent blueprints in a team |
| `Ichor.Workshop.CommRule` | Communication routing rule within a team blueprint |

## Key Modules

| Module | Responsibility |
|---|---|
| `Ichor.Workshop` | Ash Domain entry point |
| `Ichor.Workshop.TeamBlueprint` | Blueprint CRUD with `manage_relationship` for nested agents, links, and rules |
| `Ichor.Workshop.Persistence` | Serialization helpers for blueprint save/load |
| `Ichor.Workshop.Presets` | Built-in blueprint presets shipped with the system |
| `Ichor.Workshop.TeamSpecBuilder` | Transforms a saved blueprint into a launch-ready `TeamSpec` |
| `Ichor.Workshop.BlueprintState` | Pure value type representing in-memory workshop canvas state |

## Dependencies

- `ichor_data` -- shared `Ichor.Repo` (SQLite)
- `ichor_tmux_runtime` -- generates `TeamSpec` / `AgentSpec` for preview and launch
- `ash`, `ash_sqlite`

## Architecture Role

`ichor_workshop` is the blueprint authoring layer. Operators design team compositions
in the Workshop LiveView (in `ichor`), which persists blueprints via this domain.
The `TeamSpecBuilder` converts a blueprint into a `TeamSpec` that the fleet lifecycle
modules in `ichor` use to actually spawn tmux sessions and BEAM processes.
