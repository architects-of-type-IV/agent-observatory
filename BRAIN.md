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
  - Backend-pluggable: `state.backend` dispatches to tmux/SSH/webhook channel
  - Pause/resume: buffers messages when paused, delivers on resume
  - `send_message/2`, `get_state/1`, `get_unread/1`, `pause/1`, `resume/1`
- **TeamSupervisor** DynamicSupervisor: one per team, children are AgentProcesses
  - Registers in `Observatory.Fleet.TeamRegistry` (Elixir.Registry, :unique)
  - Configurable restart strategies: :one_for_one, :rest_for_one, :one_for_all
  - `spawn_member/2`, `terminate_member/2`, `member_ids/1`
- **FleetSupervisor** DynamicSupervisor: top-level, holds teams + standalone agents
  - `create_team/1`, `disband_team/1`, `spawn_agent/1`
- **Coexistence**: old ETS-based system (AgentRegistry, TeamWatcher, Mailbox, CommandQueue) still runs alongside. Migration is incremental.
- **PubSub topic**: `"fleet:lifecycle"` for agent_started/stopped/paused/resumed, team_created/disbanded
- **PubSub topic**: `"messages:stream"` for message_delivered events

## Architecture (Legacy Layer -- Still Running)
- Event-driven: hooks -> POST /api/events -> EventBuffer ETS + PubSub -> LiveView
- **Unified agent index**: `DashboardState.build_agent_index/3` merges AgentRegistry + events
- DashboardState.recompute/1 called from mount and every handle_event/handle_info
- Dashboard subscribes to `"gateway:registry"` -- recomputes on `:registry_changed`
- Ash domains: Events (SQLite), Costs (SQLite), AgentTools (MCP), Fleet (Simple/ETS), Activity (Simple/ETS)

## Ash Struct Access (CRITICAL)
- **Ash resource structs do NOT support bracket access** `[:field]`
- Team members from `{:array, :map}` attributes ARE plain maps -- bracket access works
- Use dot access `struct.field` on Ash resources, bracket access on plain maps only

## MCP Server (Agent Tools)
- Route: `forward "/mcp", AshAi.Mcp.Router` in router.ex (no pipeline)
- AshAi nests tool arguments under `"input"` key
- 5 tools: check_inbox, acknowledge_message, send_message, get_tasks, update_task_status

## Heartbeat System
- `Observatory.Heartbeat` GenServer in MonitorSupervisor, 5s interval
- **PubSub only** -- no Gateway routing. Internal ticks must NOT flow through messaging pipeline.
- Subscribers: ProtocolTracker (stats), LiveView (tmux refresh when overlay open)
- Single timer for the system -- no individual GenServer timers

## Gateway Pipeline (Legacy -- Being Replaced)
- 3 message paths through Router: Dashboard, Hook intercept, MCP send_message
- Channel registry: `config :observatory, :channels` -- list of `{module, opts}` tuples
- Channel behaviour: `channel_key/0`, `deliver/2`, `available?/1`, optional `skip?/1`
- **Fallback**: When Gateway returns 0 recipients, Operator falls back to direct Mailbox.send_message
- CommandQueue: `~/.claude/inbox/{session_id}/{id}.json`

## Tmux Delivery (CRITICAL)
- **Use named `set-buffer` + `paste-buffer`** -- NOT temp files with `cat`
- Named buffers (`obs-{unique_int}`) prevent concurrent corruption
- `Tmux.run_command/1`: public API, all callers should use this
- Observatory tmux socket: `~/.observatory/tmux/obs.sock`

## SSH Tmux Channel
- Address format: `"session_name@host"`, `ssh -o BatchMode=yes`
- PaneMonitor captures from both local and remote tmux sessions

## AgentRegistry (Legacy ETS)
- `build_lookup/1`: expands all known IDs (id, session_id, short_name) into deduped map
- `dedup_by_status/1`: prefers active over ended entries for same key
- Identity merge: CWD correlation merges UUID-keyed (hook) and short-name-keyed (team)
- Stale sweep: 3-tier (dead teams, ended 30min, stale standalone 1h)

## ProtocolTracker Performance (CRITICAL)
- `compute_stats/0` must NEVER do N+1 GenServer calls or filesystem scans
- Mount uses `%{}` default for protocol_stats, NOT get_stats

## Component Patterns
- Large components split: `.ex` (logic) + `.heex` (templates via `embed_templates`)
- Module size limit: 200-300 lines max
- Handler modules: imported via `import`
- **Feed wiring**: activity_tab assign (:comms | :feed | :costs) controls view

## User Preferences
- Zero warnings policy: `mix compile --warnings-as-errors`
- Minimal JavaScript -- "LiveView was made to limit JS usage"
- Write idiomatic Elixir, no mixing imperative/declarative
- Roadmap files: flat directory, dotted numbering, NO subdirectories
- **BEAM-native vision**: "Supervisor, genserver, process with mailboxes. These are primitives."
- **Agent agnostic**: the BEAM process IS the agent identity, tmux/SSH is just swappable backend
