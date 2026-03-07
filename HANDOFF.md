# Observatory - Handoff

## Current Status: Heartbeat + Messaging Fixes (2026-03-08)

### Just Completed
- **Heartbeat GenServer** -- `Observatory.Heartbeat` publishes `{:heartbeat, count}` every 5s to PubSub `"heartbeat"` topic AND routes through Gateway (`"fleet:heartbeat"`). Added to MonitorSupervisor. Single timer for the whole system.
- **ProtocolTracker timeout fix** -- `compute_stats/0` was doing N+1 GenServer calls (per-agent `get_messages` + per-session filesystem scans). Mount called `get_stats` synchronously -> 5s timeout -> LiveView crash. Fixed: mount uses `%{}` default, `compute_stats` now only reads ETS (fast). Removed `mailbox_detail`, `queue_detail`, `recent_traces` from stats. ProtocolTracker now subscribes to heartbeat instead of its own timer.
- **Dropdown stability** -- Wrapped target select and project select in `phx-update="ignore"` divs in `command_view.html.heex`. Selects no longer close on re-render from PubSub events.
- **Message delivery fallback** -- `Operator.send` now falls back to direct `Mailbox.send_message` when Gateway routing returns 0 recipients (agents not registered in AgentRegistry). Messages always land in ETS + `~/.claude/inbox/`.
- **Removed all polling** -- No more `poll_tmux` timer. Tmux refreshes on heartbeat (only when overlay is open) and after `send_tmux_keys`.
- **Removed longpoll transport** from endpoint.ex.

### Open Issues
1. **Build lock contention** -- Phoenix dev server holds build lock continuously. `mix compile` from CLI waits indefinitely. Dev server auto-compiles on file change though.
2. **Grey dots on team members** -- Agents from config.json without hook events default to `:idle`. Correct behavior.
3. **Detail panel click** -- Should work now (AccessStruct crash resolved in prior session).
4. **User wants**: heartbeat through gateway (done), auto-discover teams/agents (exists in AgentRegistry + TeamWatcher + SwarmMonitor).

### Architecture
- Phoenix LiveView on port 4005
- Event-driven: hooks -> POST /api/events -> EventBuffer ETS + PubSub -> LiveView
- **Heartbeat**: `Observatory.Heartbeat` -> PubSub "heartbeat" + Gateway "fleet:heartbeat"
- Subscribers react to heartbeat: ProtocolTracker (stats), LiveView (tmux refresh when overlay open)
- Ash domains: Fleet (Team, Agent), Activity (Message, Task, Error) -- all `Ash.DataLayer.Simple`
- Zero warnings: `mix compile --warnings-as-errors`

### Key Files Modified This Session
| File | Change |
|------|--------|
| `lib/observatory/heartbeat.ex` | NEW -- heartbeat GenServer, PubSub + Gateway broadcast |
| `lib/observatory/operator.ex` | Fallback to direct Mailbox when Gateway returns 0 |
| `lib/observatory/protocol_tracker.ex` | Removed N+1 stats, subscribe to heartbeat |
| `lib/observatory/monitor_supervisor.ex` | Added Heartbeat to children |
| `lib/observatory_web/live/dashboard_live.ex` | Heartbeat handler (tmux), empty protocol_stats default, removed poll_tmux |
| `lib/observatory_web/components/command_components/command_view.html.heex` | phx-update="ignore" on selects |
| `lib/observatory_web/endpoint.ex` | Removed longpoll transport |
