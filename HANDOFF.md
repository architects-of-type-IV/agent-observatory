# Observatory - Handoff

## Current Status: HITL Controls Wired (2026-03-08)

### Just Completed
- **HITL inline controls on fleet detail panel** -- Task 7 complete. Pause/Resume buttons now wire through HITLRelay (message buffering) alongside CommandQueue/Mailbox. Detail panel shows HITL Gate Open section when paused: buffered message viewer, Approve & Flush, Reject (discard) buttons. Fleet tree shows amber PAUSED badge on paused agents. Info section shows "(HITL paused)" status.
- **HITLRelay API expansion** -- Added `buffered_messages/1`, `paused_sessions/0`, `reject/3` to expose buffer state to UI. Reject discards buffer without flushing.
- **PubSub integration** -- Dashboard subscribes to `session:hitl:{session_id}` on pause, handle_info triggers recompute on gate open/close events.

### Prior Work (same day)
- Heartbeat Gateway removal, ghost agent cleanup
- Layering inversion fix (Fleet.AgentHealth), dashboard extraction (887->458 lines)
- Feed view wiring (Comms/Feed tab toggle)
- ETS scan optimization, named tmux buffers, identity merge, debug endpoints

### Open Issues
1. **dashboard_live.ex at 465 lines** -- Still above 200-300 target. Mostly one-line handle_event delegations.
2. **Build lock contention** -- Phoenix dev server holds build lock; `mix compile` from CLI waits.
3. **Tmux multi-panel** (task 15) -- User wants multi-tmux view, not just single button.
4. **Non-blocking event pipeline validation** (task 8) -- Load test hook events.

### Architecture
- Phoenix LiveView on port 4005
- Event-driven: hooks -> POST /api/events -> EventBuffer ETS + PubSub -> LiveView
- 3 message paths (all through Gateway): Dashboard, Hook intercept, MCP
- **HITL pipeline**: HITLRelay buffers messages when paused, Approve flushes, Reject discards. Auto-abandons after 30min. PubSub on `session:hitl:{session_id}`.
- AgentRegistry: ETS-backed, identity merge via CWD, UUID-only registration, ghost filtering
- Ash domains: Fleet (Team, Agent), Activity (Message, Task, Error) -- `Ash.DataLayer.Simple`

### Key Files Modified This Session
| File | Change |
|------|--------|
| `lib/observatory/gateway/hitl_relay.ex` | Added buffered_messages/1, paused_sessions/0, reject/3 |
| `lib/observatory_web/live/dashboard_session_control_handlers.ex` | Wire pause/resume to HITLRelay, add hitl_approve/reject |
| `lib/observatory_web/live/dashboard_live.ex` | HITL handle_info + handle_event clauses |
| `lib/observatory_web/components/command_components/command_view.html.heex` | HITL badges, buffer viewer, approve/reject UI |
