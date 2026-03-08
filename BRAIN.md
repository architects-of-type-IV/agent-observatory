# ICHOR IV (formerly Observatory) - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents, part of Kardashev Type IV suite
- **Architect**: the user -- has authority over everything
- **Archon**: ICHOR IV personified as top-level coordinator -- interprets Architect's will, drives fleet
- ADR-001: vendor-agnostic fleet control, ADR-002: ICHOR IV identity
- ADR-023/024/025: BEAM-native agent processes, team supervision, native messaging

## BEAM-Native Fleet Architecture (Type IV Foundation)
- **AgentProcess** GenServer: PID = identity, process mailbox = delivery target
  - Registers in `Observatory.Fleet.ProcessRegistry` (Elixir.Registry, :unique)
  - Backend-pluggable: `state.backend` dispatches via `Delivery` module (pattern-matched heads)
  - Pause/resume: buffers messages when paused, delivers on resume
  - `send_message/2`, `get_state/1`, `get_unread/1`, `pause/1`, `resume/1`
- **AgentProcess.Delivery**: Pure stateless module for message normalization + backend dispatch
  - `normalize/2` (map or string input), `deliver/2` (nil/tmux/ssh_tmux/webhook), `broadcast/2`
- **TeamSupervisor** DynamicSupervisor: one per team, children are AgentProcesses
  - Registers in `Observatory.Fleet.TeamRegistry` (Elixir.Registry, :unique)
  - Configurable restart strategies: :one_for_one, :rest_for_one, :one_for_all
- **FleetSupervisor** DynamicSupervisor: top-level, holds teams + standalone agents
- **Coexistence**: old ETS-based system still runs alongside. Migration is incremental.
- **PubSub topics**: `"fleet:lifecycle"`, `"messages:stream"`

## Ash Domain Model (Current -- Needs Redesign)
- **Fleet domain**: Agent + Team (DataLayer.Simple, read-only via preparations)
  - Gap: No write actions. All writes bypass Ash (raw GenServer calls)
  - Need: Generic actions on Agent/Team that delegate to GenServer layer
  - Need: Code interfaces for lifecycle operations
- **Activity domain**: Message + Task + Error (DataLayer.Simple, read-only)
- **AgentTools domain**: Inbox + Memory (generic actions for MCP)
  - Duplicates Fleet logic (send_message, check_inbox call GenServers directly)
  - Should delegate to Fleet code interfaces instead
- **Events domain**: Event + Session (SQLite)
- **Costs domain**: TokenUsage (SQLite)

## Elixir Style Guide (Enforced)
- Pattern matching on function heads, NOT if/else/cond
- `@doc`/`@spec` on publics, `@spec` on privates (no @doc)
- `@type` definitions for key data shapes
- Modules <=200 lines (GenServers may exceed with full annotations)
- Functions <=20 lines, args <=2-3
- No nested modules, one defmodule per file
- Pipelines for data flow, case for simple tuple matching
- Skip @doc on @impl callback functions

## Architecture (Legacy Layer -- Still Running)
- Event-driven: hooks -> POST /api/events -> EventBuffer ETS + PubSub -> LiveView
- DashboardState.recompute/1 called from mount and every handle_event/handle_info
- Ash domains: Events (SQLite), Costs (SQLite), AgentTools (MCP), Fleet (Simple/ETS), Activity (Simple/ETS)

## Ash Struct Access (CRITICAL)
- **Ash resource structs do NOT support bracket access** `[:field]`
- Team members from `{:array, :map}` attributes ARE plain maps -- bracket access works
- Use dot access `struct.field` on Ash resources, bracket access on plain maps only

## MCP Server (Agent Tools)
- Route: `forward "/mcp", AshAi.Mcp.Router` in router.ex (no pipeline)
- AshAi nests tool arguments under `"input"` key
- 15 tools: 5 inbox + 10 memory (Letta-compatible)

## Heartbeat System
- `Observatory.Heartbeat` GenServer in MonitorSupervisor, 5s interval
- **PubSub only** -- no Gateway routing. Internal ticks must NOT flow through messaging pipeline.
- Single timer for the system -- no individual GenServer timers

## Gateway Pipeline (Legacy -- Being Replaced by BEAM-native)
- 3 message paths through Router: Dashboard, Hook intercept, MCP send_message
- Channel registry: `config :observatory, :channels` -- list of `{module, opts}` tuples
- Channel behaviour: `channel_key/0`, `deliver/2`, `available?/1`, optional `skip?/1`
- **Fallback**: When Gateway returns 0 recipients, Operator falls back to direct Mailbox.send_message

## Tmux Delivery (CRITICAL)
- **Use named `set-buffer` + `paste-buffer`** -- NOT temp files with `cat`
- Named buffers (`obs-{unique_int}`) prevent concurrent corruption
- Observatory tmux socket: `~/.observatory/tmux/obs.sock`

## Component Patterns
- Large components split: `.ex` (logic) + `.heex` (templates via `embed_templates`)
- Handler modules: imported via `import`
- **Format-on-save race**: Edit tool fails when hooks modify file between Read and Edit

## User Preferences
- Zero warnings policy: `mix compile --warnings-as-errors`
- Minimal JavaScript -- "LiveView was made to limit JS usage"
- **BEAM-native vision**: "Supervisor, genserver, process with mailboxes. These are primitives."
- **Agent agnostic**: the BEAM process IS the agent identity, tmux/SSH is just swappable backend
- **"It all needs to be rooted in Elixir and idiomatic Ash"**
- ADR-001 + ADR-002 = THE GOAL. Everything works toward sovereign fleet control.
