# Observatory - Handoff

## Current Status: Tmux Multi-Panel + HITL Controls (2026-03-08)

### Just Completed
- **Tmux multi-panel** (task 15) -- Replaced single-session modal with tabbed multi-panel. Multiple sessions open simultaneously via tab bar. Tiled layout option (2-column grid, all panes visible, click to focus). Heartbeat refreshes ALL open panels. Close Tab / Close All / Kill / Layout toggle.
- **New assigns**: `tmux_panels` (list), `tmux_outputs` (map), `tmux_layout` (:tabs/:tiled)
- **HITL inline controls** (task 7) -- Pause wires through HITLRelay. Buffer viewer + approve/reject in detail panel. PAUSED badge in fleet tree.

### Prior Work (same day)
- Heartbeat Gateway removal, ghost agent cleanup
- Layering inversion fix, dashboard extraction (887->458 lines), feed view wiring
- ETS scan optimization, named tmux buffers, identity merge, debug endpoints

### Open Issues
1. **dashboard_live.ex at 465 lines** -- Mostly one-line handle_event delegations.
2. **Build lock contention** -- Phoenix dev server holds build lock.
3. **Non-blocking event pipeline validation** (task 8) -- Load test hook events.

### Architecture
- Phoenix LiveView on port 4005
- Event-driven: hooks -> POST /api/events -> EventBuffer ETS + PubSub -> LiveView
- **Tmux multi-panel**: tmux_panels list, tmux_outputs map, :tabs/:tiled layout. Heartbeat refreshes all.
- **HITL pipeline**: HITLRelay buffers when paused, approve flushes, reject discards. PubSub `session:hitl:{sid}`.
- AgentRegistry: ETS-backed, identity merge, UUID-only registration, ghost filtering
- Ash domains: Fleet (Team, Agent), Activity (Message, Task, Error)

### Key Files Modified This Session
| File | Change |
|------|--------|
| `lib/observatory_web/live/dashboard_tmux_handlers.ex` | Multi-panel: connect adds tab, refresh_tmux_panels, toggle_tmux_layout |
| `lib/observatory_web/live/dashboard_live.html.heex` | Tabbed/tiled tmux modal, tab bar, layout toggle |
| `lib/observatory_web/live/dashboard_state.ex` | tmux_panels, tmux_outputs, tmux_layout assigns |
| `lib/observatory_web/live/dashboard_live.ex` | Multi-tmux events, heartbeat multi-refresh |
| `lib/observatory/gateway/hitl_relay.ex` | buffered_messages/1, paused_sessions/0, reject/3 |
| `lib/observatory_web/live/dashboard_session_control_handlers.ex` | HITLRelay wiring, hitl_approve/reject |
| `lib/observatory_web/components/command_components/command_view.html.heex` | HITL badges, buffer viewer |
