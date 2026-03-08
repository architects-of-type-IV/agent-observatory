# Observatory - Brain

## Architecture
- Event-driven: hooks -> POST /api/events -> EventBuffer ETS + PubSub -> LiveView
- Dual data sources: event-derived state + disk-based team/task state (TeamWatcher)
- DashboardState.recompute/1 called from mount and every handle_event/handle_info
- Ash domains: Events (SQLite), Costs (SQLite), AgentTools (MCP), Fleet (Simple/ETS), Activity (Simple/ETS)

## Ash Struct Access (CRITICAL)
- **Ash resource structs do NOT support bracket access** `[:field]`
- Team members from `{:array, :map}` attributes ARE plain maps -- bracket access `m[:name]` works
- Rule: use dot access `struct.field` on Ash resources, bracket access on plain maps only
- `Map.get(struct, :field, default)` works on structs when you need a fallback

## Ash Domain Model (2026-03-07)
- Fleet domain: Agent + Team resources, backed by Ash.DataLayer.Simple
- Activity domain: Message + Task + Error resources, backed by Ash.DataLayer.Simple
- Pattern: shared Preparations load data via set_data/2, Ash applies filter DSL
- Code interfaces: Fleet.Agent.active!(), Fleet.Team.alive!(), Activity.Error.by_tool!()

## MCP Server (Agent Tools)
- Route: `forward "/mcp", AshAi.Mcp.Router` in router.ex (no pipeline)
- AshAi nests tool arguments under `"input"` key
- 5 tools: check_inbox, acknowledge_message, send_message, get_tasks, update_task_status

## Heartbeat System (2026-03-08)
- `Observatory.Heartbeat` GenServer in MonitorSupervisor, 5s interval
- **PubSub only** -- publishes `{:heartbeat, count}` on `"heartbeat"` topic. No Gateway routing.
- Subscribers: ProtocolTracker (stats broadcast), LiveView (tmux refresh when overlay open)
- **Maintenance**: every 60 beats (5min), spawns `AgentRegistry.purge_stale()`
- Single timer for the system -- no individual GenServer timers
- **Design lesson**: internal ticks must NOT flow through the messaging pipeline (Gateway). Causes mailbox flooding, trace eviction, wasted audit broadcasts. PubSub direct is correct for system signals.

## AgentRegistry Ghost Prevention (2026-03-08)
- `register_from_event` rejects non-UUID session IDs (blocks curl test probes)
- `poll_tmux_sessions` filters via `observatory_session?/1`: `"obs"`, `"obs-*"`, numeric names
- `sweep_ended_agents` removes non-UUID standalones and observatory sessions
- Three-layer defense: registration gate, poll filter, sweep cleanup

## Gateway Pipeline (3 message paths, all unified through Router)
1. **Dashboard -> Agent**: Operator.send -> Gateway.Router.broadcast -> MailboxAdapter + Tmux + Webhook
2. **Hook intercept -> Agent**: EventController handle_send_message -> Gateway.Router.broadcast
3. **Agent -> Dashboard**: MCP send_message -> Gateway.Router.broadcast
- **Fallback**: When Gateway returns 0 recipients, Operator falls back to direct Mailbox.send_message
- CommandQueue: `~/.claude/inbox/{session_id}/{id}.json`
- **ClearFormOnSubmit** hook clears text inputs 50ms after submit

## Tmux Delivery (CRITICAL)
- **Use named `set-buffer` + `paste-buffer`** -- NOT temp files with `cat`
- Old approach (`cat /tmp/observatory_msg_*.txt`) triggers file read permission in Claude Code agents
- New approach: `set-buffer -b NAME MSG` then `paste-buffer -b NAME -d -t TARGET` then `send-keys Enter`
- Named buffers (`obs-{unique_int}`) prevent concurrent deliveries from corrupting each other
- `-d` flag auto-deletes buffer after paste
- **`Tmux.run_command/1`**: public API for `try_tmux` -- all callers should use this, not direct `System.cmd`
- **`server_arg_sets` cached**: 5s TTL via `Process.put/get` to avoid repeated `File.exists?` stat calls
- **Skip tmux for system messages**: Router filters out `:heartbeat` and `:system` types from tmux delivery

## AgentRegistry (2026-03-08)
- ETS table `:gateway_agent_registry`, merges hook events + TeamWatcher + tmux polling
- **Qualified IDs**: `"name@team"` format, with `short_name` for backward lookups
- **Identity merge**: CWD correlation merges UUID-keyed (hook) and short-name-keyed (team) entries
  - `find_canonical_entry/4`: takes pre-built cwd index, tries existing team match, then cwd lookup, then fallback
  - `correlate_by_cwd/2`: O(1) lookup from pre-built index (was O(N) full scan per member)
  - `maybe_absorb_team_entry/2`: uses `ets.match_object` to filter by cwd server-side (was full `tab2list`)
  - `is_uuid?/1`: uses `Ecto.UUID.cast/1` (not hand-rolled)
  - Ambiguous cases (multiple agents same CWD) gracefully fall back to separate entries
- **Broadcast**: sends `:registry_changed` signal, NOT full table. Subscribers call `list_all()` lazily.
- **Stale sweep**: 3-tier (dead teams, ended 30min TTL, stale standalones 1h TTL)
- **Operator**: permanent agent registered at init, never swept

## Debug Endpoints (2026-03-08)
- `GET /api/debug/registry` -- all agents with channels, status, team
- `GET /api/debug/health` -- registry, team_watcher, pubsub, mailbox, event_buffer, ets_tables
- `GET /api/debug/traces?limit=50&type=message` -- ProtocolTracker traces with hops
- `GET /api/debug/mailboxes` -- per-agent stats + recent messages
- `GET /api/debug/tmux` -- sessions, panes, agents_with_tmux, socket_args
- `POST /api/debug/purge` -- manual stale agent sweep

## ProtocolTracker Performance (CRITICAL)
- `compute_stats/0` must NEVER do N+1 GenServer calls or filesystem scans
- Current version: ETS reads only + single `Mailbox.get_stats` call
- Mount uses `%{}` default for protocol_stats, NOT `get_stats` (avoids blocking)

## LiveView Re-render Stability
- `phx-update="ignore"` on select dropdowns prevents closing on re-render
- `phx-update="ignore"` on text inputs preserves user typing
- No polling timers in LiveView -- fully PubSub-driven + heartbeat

## Fleet Tree Rendering
- FleetHelpers.sort_members: classifies by member name string
- Hierarchy via indent: `20 + depth * 32` px padding-left
- Tree connectors: unicode characters
- Status dots: `:active` = emerald, `:idle` = zinc-500, `:ended` = zinc-700

## HITL Pipeline (2026-03-08)
- HITLRelay GenServer buffers messages when session paused, flushes on approve, discards on reject
- API: `pause/4`, `unpause/3`, `reject/3`, `buffered_messages/1`, `paused_sessions/0`, `session_status/1`
- PubSub: `session:hitl:{session_id}` -- GateOpenEvent / GateCloseEvent
- Dashboard subscribes on pause, handle_info recomputes on gate events
- Auto-abandons after 30min (sweep timer)
- Pause sends BOTH HITLRelay.pause + CommandQueue/Mailbox command to agent
- Fleet tree shows amber PAUSED badge, detail panel shows buffer viewer + approve/reject

## Component Patterns
- Large components split: `.ex` (logic) + `.heex` (templates via `embed_templates`)
- Module size limit: 200-300 lines max
- Handler modules: imported via `import`, NOT called with full module names or `apply/3`
- **Layering fix**: `Fleet.AgentHealth` (domain) owns compute_agent_health/2. Web helper delegates.
- **Feed wiring**: FeedComponents.feed_view/1 rendered via Comms/Feed tab toggle in command_view center column. `activity_tab` assign (:comms | :feed) controls which view shows.
- **Mount consolidation**: `DashboardState.default_assigns/1` returns all initial assigns as a map

## Tmux Multi-Panel (2026-03-08)
- **Multi-session**: `tmux_panels` (list), `tmux_outputs` (map of session->output), `tmux_layout` (:tabs/:tiled)
- `connect_tmux` adds to panels list (or switches if already open), `disconnect_tmux` closes active tab
- `refresh_tmux_panels/1` refreshes ALL open sessions on heartbeat (not just active)
- Tiled layout: 2-column grid, all panes visible, click to focus. Active gets amber ring.
- `active_tmux_session` still tracks which tab has keyboard focus for send_keys

## Observatory tmux socket
- Path: `~/.observatory/tmux/obs.sock`
- Auto-started in Application.start via `ensure_tmux_server/0`
- All tmux ops try this socket first, fall back to default

## User Preferences
- Zero warnings policy: `mix compile --warnings-as-errors`
- Minimal JavaScript -- "LiveView was made to limit JS usage"
- Write idiomatic Elixir, no mixing imperative/declarative
- Roadmap files: flat directory, dotted numbering, NO subdirectories
