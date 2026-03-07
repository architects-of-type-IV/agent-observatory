# Observatory - Brain

## Architecture
- Event-driven: hooks -> POST /api/events -> EventBuffer ETS + PubSub -> LiveView
- Dual data sources: event-derived state + disk-based team/task state (TeamWatcher)
- DashboardState.recompute/1 called from mount and every handle_event/handle_info
- Ash domains: Events (SQLite), Costs (SQLite), AgentTools (MCP), Fleet (Simple/ETS), Activity (Simple/ETS)

## Ash Struct Access (CRITICAL)
- **Ash resource structs do NOT support bracket access** `[:field]`
- `use Observatory.AccessStruct` was tried and FAILED -- Ash's `@before_compile` hooks strip the `fetch/2` function
- Team members from `{:array, :map}` attributes ARE plain maps -- bracket access `m[:name]` works
- Rule: use dot access `struct.field` on Ash resources, bracket access on plain maps only
- `Map.get(struct, :field, default)` works on structs when you need a fallback

## Ash Domain Model (2026-03-07)
- Fleet domain: Agent + Team resources, backed by Ash.DataLayer.Simple
- Activity domain: Message + Task + Error resources, backed by Ash.DataLayer.Simple
- Pattern: shared Preparations load data via set_data/2, Ash applies filter DSL
- Code interfaces: Fleet.Agent.active!(), Fleet.Team.alive!(), Activity.Error.by_tool!()
- LoadAgents calls Fleet.Team.alive!() for team enrichment (no circular dep)

## MCP Server (Agent Tools)
- Route: `forward "/mcp", AshAi.Mcp.Router` in router.ex (no pipeline)
- AshAi nests tool arguments under `"input"` key
- 5 tools: check_inbox, acknowledge_message, send_message, get_tasks, update_task_status

## Heartbeat System (2026-03-08)
- `Observatory.Heartbeat` GenServer in MonitorSupervisor, 5s interval
- Publishes to PubSub "heartbeat" AND Gateway "fleet:heartbeat"
- Subscribers: ProtocolTracker (stats broadcast), LiveView (tmux refresh when overlay open)
- Single timer for the system -- no individual GenServer timers

## Messaging Pipeline
- Dashboard -> Agent: Operator.send -> Gateway.Router.broadcast -> MailboxAdapter -> Mailbox ETS + CommandQueue filesystem
- **Fallback**: When Gateway returns 0 recipients, Operator falls back to direct Mailbox.send_message (bypasses registry)
- Agent -> Dashboard: MCP send_message -> Gateway.Router.broadcast (same pipeline)
- CommandQueue: `~/.claude/inbox/{session_id}/{id}.json`
- acknowledge_message cleans both ETS and CommandQueue files
- **ClearFormOnSubmit** hook clears text inputs 50ms after submit

## ProtocolTracker Performance (CRITICAL)
- `compute_stats/0` must NEVER do N+1 GenServer calls or filesystem scans
- Old version called `Mailbox.get_messages` per agent + `CommandQueue.get_pending_commands` per session -> timeout on mount
- Current version: ETS reads only + single `Mailbox.get_stats` call
- Mount uses `%{}` default for protocol_stats, NOT `get_stats` (avoids blocking)

## LiveView Re-render Stability
- `phx-update="ignore"` on select dropdowns prevents closing on re-render
- `phx-update="ignore"` on text inputs preserves user typing
- No polling timers in LiveView -- fully PubSub-driven + heartbeat

## Fleet Tree Rendering
- FleetHelpers.sort_members: classifies by member name string ("coordinator" -> depth 0, "lead" -> depth 1, "worker" -> depth 2)
- Hierarchy via indent: `20 + depth * 32` px padding-left
- Tree connectors: unicode characters (U+2514 corner, U+251C tee)
- Status dots: `:active` = emerald, `:idle` = zinc-500 (grey), `:ended` = zinc-700
- Teams grouped by project (derived from member cwds)

## Component Patterns
- Large components split: `.ex` (logic) + `.heex` (templates via `embed_templates`)
- Module size limit: 200-300 lines max
- Preprocessing in `<% %>` blocks at top of .heex templates
- Multi-head pattern-matched dispatch stays as `defp` in .ex

## Observatory tmux socket
- Path: `~/.observatory/tmux/obs.sock`
- Auto-started in Application.start via `ensure_tmux_server/0`
- All tmux ops try this socket first, fall back to default

## User Preferences
- Zero warnings policy: `mix compile --warnings-as-errors`
- Minimal JavaScript -- "LiveView was made to limit JS usage"
- Write idiomatic Elixir, no mixing imperative/declarative
- Helpers could be Ash resource actions (user suggestion for future refactor)
- Roadmap files: flat directory, dotted numbering, NO subdirectories
