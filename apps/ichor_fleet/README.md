# ichor_fleet

Ash Domain for agent and team data models. The canonical API for all agent lifecycle and
messaging operations.

## Ash Domains

**`Ichor.Fleet`** -- owns two resources backed by `Ash.DataLayer.Simple` (no database table).
State is loaded at read time from the BEAM process registry; writes delegate to GenServer hooks.

| Resource | Description |
|---|---|
| `Ichor.Fleet.Agent` | An active or historical agent in the fleet |
| `Ichor.Fleet.Team` | A named team grouping one or more agents |

## Key Modules

| Module | Responsibility |
|---|---|
| `Ichor.Fleet` | Ash Domain entry point |
| `Ichor.Fleet.Agent` | Agent resource with `spawn`, `launch`, `terminate_agent`, `send_message`, `get_unread`, `update_instructions` actions |
| `Ichor.Fleet.Team` | Team resource with `create`, `list`, `terminate_team` actions |
| `Ichor.Fleet.Views.Preparations.LoadAgents` | Populates agents at read time from the BEAM runtime registry |
| `Ichor.Fleet.Views.Preparations.LoadTeams` | Populates teams at read time from the BEAM runtime registry |

## Runtime Hook Pattern

`Ichor.Fleet.Agent` resolves its runtime module via:

```elixir
Application.get_env(:ichor_fleet, :runtime_hooks_module, Module.concat([Ichor, Fleet, RuntimeHooks]))
```

This allows the actual GenServer/Registry calls to live in `ichor` (main app) while the
resource definition stays in `ichor_fleet` (no circular dependency).

## Dependencies

- `ash` -- Ash framework only; no database dependency

## Architecture Role

`ichor_fleet` defines the shape and API contract for agent and team operations.
The runtime implementation (GenServers, Registry, tmux launch) lives in `ichor`.
All external code that needs to interact with agents goes through `Ichor.Fleet.Agent`
and `Ichor.Fleet.Team` code interfaces, not directly to the runtime.
