# Observatory - Handoff

## Current Status: AccessStruct Removal + Fleet Fixes (2026-03-07)

### Just Completed
- **Removed AccessStruct macro from all Ash resources** -- `use Observatory.AccessStruct` was incompatible with Ash's compilation hooks. `fetch/2` was stripped at compile time, causing runtime `UndefinedFunctionError` crashes on every `:tick`. Removed from Fleet.Team, Fleet.Agent, Activity.Error, Activity.Task, Activity.Message.
- **Converted all bracket access on Ash structs to dot access** -- Fixed ~25 callsites across 10 files: fleet_helpers.ex, dashboard_state.ex, dashboard_team_inspector_handlers.ex, dashboard_live.ex, dashboard_team_helpers.ex, dashboard_feed_helpers.ex, team_inspector_components.ex, team_message_components.ex, teams_components.ex, protocol_components.ex, team_tmux_components.ex.
- **Removed longPollFallbackMs** -- Was set to 2500 in app.js, removed per user request.
- **Fleet indentation fix** -- `sort_members` was passing whole member map to `classify_role` (catch-all `:member`). Fixed to pass `m[:name] || m[:agent_type]` for correct role->depth mapping.

### Key Learning: Ash Structs and Access
Ash resource structs do NOT support bracket access `[:field]`. The `@behaviour Access` + `@impl Access` functions defined via `use` macro get stripped by Ash's `@before_compile` hooks. Use dot access (`struct.field`) or `Map.get(struct, :field, default)` instead. Team members (from `{:array, :map}` attributes) ARE plain maps and DO support bracket access.

### Open Issues (User Reported)
1. **Grey dots on comms-test team** -- Team members from config.json without hook events show `:idle` status (grey). This is correct behavior if agents aren't active, but user questions if team is offline.
2. **Detail panel not showing on click** -- `handle_select_command_agent` sets `selected_command_agent` assign, template shows panel with `:if={selected}`. Was blocked by compilation crash (AccessStruct). Should work now with clean compile.
3. **User notes**: "Most helpers could be Ash resource actions" and "Write idiomatic Elixir, no mixing imperative/declarative"

### Architecture
- Phoenix LiveView on port 4005
- Event-driven: hooks -> POST /api/events -> EventBuffer ETS + PubSub -> LiveView
- Ash domains: Fleet (Team, Agent), Activity (Message, Task, Error) -- all `Ash.DataLayer.Simple`
- Zero warnings: `mix compile --warnings-as-errors`

### Key Files Modified This Session
| File | Change |
|------|--------|
| `lib/observatory/fleet/team.ex` | Removed AccessStruct |
| `lib/observatory/fleet/agent.ex` | Removed AccessStruct |
| `lib/observatory/activity/{error,task,message}.ex` | Removed AccessStruct |
| `lib/observatory_web/components/fleet_helpers.ex` | `t[:members]` -> `Map.get(t, :members, [])`, `t[:name]` -> `t.name` |
| `lib/observatory_web/live/dashboard_state.ex` | `t[:name]` -> `t.name` |
| `lib/observatory_web/live/dashboard_team_helpers.ex` | `team[:members]` -> `Map.get(team, :members, [])`, `team[:lead_session]` -> `team.lead_session` |
| `lib/observatory_web/components/{team_inspector,team_message,teams,protocol,team_tmux}_components.ex` | All bracket -> dot access |
| `assets/js/app.js` | Removed longPollFallbackMs |
