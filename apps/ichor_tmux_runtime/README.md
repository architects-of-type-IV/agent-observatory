# ichor_tmux_runtime

Pure tmux session and window lifecycle primitives shared across the fleet launch path.

## Ash Domains

None. This app contains only plain Elixir modules with no Ash or Ecto dependencies.

## Key Modules

| Module | Responsibility |
|---|---|
| `Ichor.Fleet.TmuxHelpers` | Shared tmux argument building (socket path, config) |
| `Ichor.Fleet.Lifecycle.TmuxLauncher` | Low-level tmux commands: `create_session`, `create_window`, `kill_session`, `send_exit`, `available?`, `list_sessions` |
| `Ichor.Fleet.Lifecycle.TmuxScript` | Shell script generation for agent startup sequences |
| `Ichor.Fleet.Lifecycle.AgentSpec` | Value type describing a single agent's launch parameters |
| `Ichor.Fleet.Lifecycle.TeamSpec` | Value type describing a team's launch parameters |

## Dependencies

- No dependencies (empty `deps` list in `mix.exs`)

## Architecture Role

`ichor_tmux_runtime` is the pure infrastructure boundary for tmux. It wraps
`System.cmd("tmux", ...)` calls behind a clean Elixir API. The `ichor` app's
`Ichor.Fleet.Lifecycle` modules call into this app to create and destroy tmux
sessions when launching or terminating agents. `ichor_workshop` also depends on
this app to preview launch specs before committing a blueprint.
