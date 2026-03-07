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

## Messaging Pipeline
- Dashboard -> Agent: LiveView form -> Mailbox.send_message/4 -> ETS + CommandQueue (filesystem)
- Agent -> Dashboard: MCP send_message -> Mailbox -> ETS + PubSub "agent:dashboard"
- CommandQueue: `~/.claude/inbox/{session_id}/{id}.json`
- acknowledge_message cleans both ETS and CommandQueue files
- **phx-update="ignore" forms still fire phx-submit** -- use JS hooks for post-submit DOM updates
- **ClearFormOnSubmit** hook clears text inputs 50ms after submit

## LiveView Timer Gotchas
- `:tick` (1s) updates assigns -> full template re-render -> select dropdowns close
- `phx-update="ignore"` prevents re-render but also prevents server-side updates to that DOM region
- Select dropdowns must be rendered server-side (NOT inside phx-update="ignore")
- Text inputs that need to survive tick: wrap in `phx-update="ignore"` with stable `id`

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
