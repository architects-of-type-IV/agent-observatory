# Observatory - Handoff

## Current Status: Dashboard Extraction + Feed Wiring (2026-03-08)

### Just Completed
- **Heartbeat Gateway removal** -- Removed `Gateway.Router.broadcast("fleet:heartbeat", ...)` from Heartbeat GenServer. Heartbeat was flooding comms timeline (every 5s to all mailboxes), evicting real protocol traces (200-cap filled in 16min), and broadcasting audit to no subscribers. PubSub direct path retained for ProtocolTracker + LiveView.
- **Ghost agent cleanup** -- `poll_tmux_sessions` now filters Observatory infrastructure sessions (`obs*`, numeric indices) via `observatory_session?/1`. `register_from_event` rejects non-UUID session IDs. Sweep removes non-UUID standalones. Purged `obs`, `0`, `obs-1772933455`, `test-123`.
- **Layering inversion fix** -- Created `Observatory.Fleet.AgentHealth` (79 lines) in domain layer.
- **Dashboard extraction (887 -> 458 lines)** -- Extracted Phase5, Slideout handlers. Consolidated mount.
- **Feed view wiring** -- Comms/Feed tab toggle in command_view center column.

### Prior Work (same day)
- ETS scan optimization, named tmux buffers, Tmux.run_command/1, server_arg_sets cache
- Identity merge in AgentRegistry, Ash domain refactor
- Gateway trace + debug endpoints, messaging unification

### Open Issues
1. **dashboard_live.ex at 458 lines** -- Still above 200-300 target. Remaining lines are mostly one-line handle_event delegations for ~90 events.
2. **Build lock contention** -- Phoenix dev server holds build lock; `mix compile` from CLI waits indefinitely.
3. **HITL controls** (task 7) -- Backend complete, needs inline approve/reject/rewrite on agent cards.
4. **Tmux multi-panel** (task 15) -- User wants multi-tmux view, not just single button.

### Architecture
- Phoenix LiveView on port 4005
- Event-driven: hooks -> POST /api/events -> EventBuffer ETS + PubSub -> LiveView
- 3 message paths (all through Gateway): Dashboard, Hook intercept, MCP
- AgentRegistry: ETS-backed, identity merge via CWD, UUID-only registration, ghost filtering
- Tmux: `Tmux.run_command/1`, named buffers, cached server_arg_sets
- Ash domains: Fleet (Team, Agent), Activity (Message, Task, Error) -- `Ash.DataLayer.Simple`
- **Domain layering**: Fleet.AgentHealth for health computation, web layer delegates

### Key Files Modified This Session
| File | Change |
|------|--------|
| `lib/observatory/fleet/agent_health.ex` | NEW: domain-layer health computation |
| `lib/observatory_web/live/dashboard_agent_health_helpers.ex` | Delegates to Fleet.AgentHealth, keeps presentation |
| `lib/observatory/fleet/preparations/load_teams.ex` | Import from domain, not web |
| `lib/observatory_web/live/dashboard_phase5_handlers.ex` | NEW: extracted Phase 5 handlers |
| `lib/observatory_web/live/dashboard_slideout_handlers.ex` | NEW: extracted slideout handlers |
| `lib/observatory_web/live/dashboard_live.ex` | 887 -> 458 lines |
| `lib/observatory_web/live/dashboard_state.ex` | Added default_assigns/1 |
| `lib/observatory_web/components/command_components/command_view.html.heex` | Comms/Feed tab toggle |
| `lib/observatory_web/components/command_components.ex` | Import FeedComponents |
| `lib/observatory_web/live/dashboard_live.html.heex` | Pass activity_tab prop |
