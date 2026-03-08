# Observatory - Handoff

## Current Status: Dashboard Extraction + Feed Wiring (2026-03-08)

### Just Completed
- **Layering inversion fix** -- Created `Observatory.Fleet.AgentHealth` (79 lines) in domain layer. `LoadTeams` now imports from domain, not web layer. `DashboardAgentHealthHelpers` delegates to domain module + keeps presentation helpers only.
- **Dashboard extraction (887 -> 458 lines)** -- Extracted `DashboardPhase5Handlers` (104 lines), `DashboardSlideoutHandlers` (125 lines). Consolidated mount into `DashboardState.default_assigns/1`. Gateway PubSub handlers use tuple matching guard.
- **Feed view wiring** -- `FeedComponents.feed_view/1` was fully implemented but never rendered. Added Comms/Feed tab toggle in command_view center column. `activity_tab` assign controls which view shows (:comms or :feed).

### Prior Work (same day)
- ETS scan optimization, named tmux buffers, Tmux.run_command/1, server_arg_sets cache
- Identity merge in AgentRegistry, Ash domain refactor, heartbeat system
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
- AgentRegistry: ETS-backed, identity merge via CWD correlation, qualified IDs
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
