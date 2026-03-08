# Observatory - Handoff

## Current Status: Gateway Pipeline Unification + Debug Endpoints (2026-03-08)

### Just Completed
- **Debug endpoints** -- 6 new routes under `/api/debug/` for system diagnostics: registry dump, health checks, protocol traces, mailbox inspection, tmux state, manual purge
- **EventController Gateway unification** -- `handle_send_message` was calling `Mailbox.send_message` directly (bypassing Gateway). Now routes through `Gateway.Router.broadcast` for consistent audit/tracing
- **Tmux pane-level delivery** -- `sync_teams` now wires `tmux_pane_id` from team config into agent channels. `poll_tmux_sessions` uses new `Tmux.list_panes()` for pane-level discovery
- **Qualified agent naming** -- Agents get `"name@team"` IDs (e.g., `"coordinator@my-team"`) with `short_name` for backward-compatible lookups. Disambiguates duplicate names across teams
- **Stale agent sweep** -- 3-tier: dead teams, ended agents (30min TTL), stale standalones (1h TTL). Manual purge via `/api/debug/purge`. Auto-sweep every 60 heartbeats (5min) via `Observatory.Heartbeat`
- **Agent blocks updated** -- `~/.claude/agents/blocks/shared/gateway-comms.md` teaches agents about Gateway architecture, qualified IDs, delivery channels

### Prior Session (same day)
- Heartbeat GenServer (5s interval, PubSub + Gateway broadcast)
- ProtocolTracker timeout fix (removed N+1 GenServer calls)
- Dropdown stability (phx-update="ignore" on selects)
- Message delivery fallback (direct Mailbox when Gateway returns 0)
- Removed all polling, removed longpoll transport

### Open Issues
1. **Identity merge** -- Hook events arrive with UUID session_ids, TeamWatcher registers with `agent_id@team` keys. These two ETS entries never merge into one unified agent record
2. **Session ID uniformity** -- User asked: "Session ids.. shouldn't those be claude code sessions or uniform?" -- not yet addressed
3. **Build lock contention** -- Phoenix dev server holds build lock; `mix compile` from CLI waits indefinitely
4. **Ash domain refactor steps 7-9** -- Move inline handlers, retire helpers, final validation

### Architecture
- Phoenix LiveView on port 4005
- Event-driven: hooks -> POST /api/events -> EventBuffer ETS + PubSub -> LiveView
- **3 message paths (all now through Gateway)**: Dashboard (Operator.send), Hook intercept (EventController), MCP (AgentTools.Inbox)
- **Heartbeat**: `Observatory.Heartbeat` -> PubSub "heartbeat" + Gateway "fleet:heartbeat"
- **AgentRegistry**: ETS-backed, merges hook events + TeamWatcher + tmux polling. Qualified IDs. Sweep on heartbeat
- Ash domains: Fleet (Team, Agent), Activity (Message, Task, Error) -- all `Ash.DataLayer.Simple`

### Key Files Modified This Session
| File | Change |
|------|--------|
| `lib/observatory_web/controllers/debug_controller.ex` | NEW -- 6 diagnostic endpoints |
| `lib/observatory_web/router.ex` | Added debug routes under /api |
| `lib/observatory_web/controllers/event_controller.ex` | Unified send_message through Gateway |
| `lib/observatory/gateway/agent_registry.ex` | Qualified IDs, tmux pane wiring, stale sweep, purge_stale |
| `lib/observatory/gateway/channels/tmux.ex` | Added list_panes(), fixed available?() for pane IDs |
| `lib/observatory/heartbeat.ex` | Added run_maintenance (registry purge every 60 beats) |
| `~/.claude/agents/blocks/registry.json` | Added gateway-comms block |
| `~/.claude/agents/blocks/shared/gateway-comms.md` | NEW -- Gateway architecture knowledge for agents |
