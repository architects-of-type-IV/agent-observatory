# Observatory - Handoff

## Current Status: Conversation Tracing + Multi-Tmux + HITL (2026-03-08)

### Just Completed
- **Conversation tracing** -- Filter comms by agent pair. Click "Trace" on an agent in detail panel to filter comms to that agent's messages. Click a second agent to narrow to pair conversation. Violet pills in comms tab bar show active trace. Max 2 agents; clicking 3rd replaces.
- **Tmux multi-panel** (task 15) -- Tabbed + tiled layout. Multiple sessions open simultaneously. Heartbeat refreshes all.
- **HITL inline controls** (task 7) -- Pause wires through HITLRelay. Buffer viewer + approve/reject in detail panel. PAUSED badge in fleet tree.
- **Coordinator/worker visibility** -- Already working via collect_agents (events + team enrichment). Trace feature completes pair filtering.

### Prior Work (same day)
- Heartbeat Gateway removal, ghost agent cleanup
- Layering inversion fix, dashboard extraction (887->458 lines), feed view wiring
- ETS scan optimization, named tmux buffers, identity merge, debug endpoints

### Open Issues
1. **dashboard_live.ex at 468 lines** -- Mostly one-line handle_event delegations.
2. **Non-blocking event pipeline validation** (task 8) -- Load test hook events. Low priority.

### Architecture
- Phoenix LiveView on port 4005
- Event-driven: hooks -> POST /api/events -> EventBuffer ETS + PubSub -> LiveView
- **Conversation trace**: `comms_agent_filter` (list of 0-2 agent IDs), `filter_by_agents/3` in FleetHelpers
- **Tmux multi-panel**: tmux_panels list, tmux_outputs map, :tabs/:tiled layout
- **HITL pipeline**: HITLRelay buffers when paused, approve flushes, reject discards
- AgentRegistry: ETS-backed, identity merge, UUID-only registration
- Ash domains: Fleet (Team, Agent), Activity (Message, Task, Error)

### Key Files Modified This Session
| File | Change |
|------|--------|
| `lib/observatory_web/components/fleet_helpers.ex` | Added filter_by_agents/3 |
| `lib/observatory_web/live/dashboard_live.ex` | trace_agent, clear_trace events |
| `lib/observatory_web/live/dashboard_state.ex` | comms_agent_filter assign |
| `lib/observatory_web/components/command_components/command_view.html.heex` | Trace button, violet pills, agent filtering |
| `lib/observatory_web/live/dashboard_live.html.heex` | Pass comms_agent_filter prop |
