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
- Publishes to PubSub "heartbeat" AND Gateway "fleet:heartbeat"
- Subscribers: ProtocolTracker (stats broadcast), LiveView (tmux refresh when overlay open)
- **Maintenance**: every 60 beats (5min), spawns `AgentRegistry.purge_stale()`
- Single timer for the system -- no individual GenServer timers

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

## Component Patterns
- Large components split: `.ex` (logic) + `.heex` (templates via `embed_templates`)
- Module size limit: 200-300 lines max
- Handler modules: imported via `import`, NOT called with full module names or `apply/3`
- **DashboardAgentHealthHelpers layering inversion**: web helper imported by LoadTeams (domain)

## Observatory tmux socket
- Path: `~/.observatory/tmux/obs.sock`
- Auto-started in Application.start via `ensure_tmux_server/0`
- All tmux ops try this socket first, fall back to default

## User Preferences
- Zero warnings policy: `mix compile --warnings-as-errors`
- Minimal JavaScript -- "LiveView was made to limit JS usage"
- Write idiomatic Elixir, no mixing imperative/declarative
- Roadmap files: flat directory, dotted numbering, NO subdirectories
