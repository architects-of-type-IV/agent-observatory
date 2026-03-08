# Observatory - Handoff

## Current Status: Identity Merge + Ash Refactor + Tmux Fix (2026-03-08)

### Just Completed
- **Identity merge in AgentRegistry** -- Hook UUID session_ids and TeamWatcher short-name keys now merge into one canonical entry. `sync_teams` correlates by CWD to find existing UUID-keyed agents. `register_from_event` absorbs orphaned team entries. `poll_tmux_sessions` skips duplicates. Ambiguous cases (shared CWD) gracefully fall back.
- **Ash domain refactor steps 7-9** -- Imported `DashboardSessionControlHandlers` + created `DashboardTmuxHandlers` (90 lines extracted). Eliminated all `apply/3` and full-module-name calls. dashboard_live.ex: 982 -> 887 lines. All helpers still actively used. Clean compile.
- **Tmux deliver fix** -- `deliver/2` now uses `set-buffer` + `paste-buffer` instead of writing temp files and `cat`-ing them. Agents no longer stall on file read permission prompts.

### Prior Work (same day)
- Debug endpoints (6 routes under /api/debug/)
- EventController Gateway unification (was bypassing Gateway)
- Tmux pane-level discovery + delivery
- Qualified agent naming ("name@team" IDs)
- Stale agent sweep (3-tier, heartbeat-driven)
- Agent blocks updated with Gateway knowledge

### Open Issues
1. **DashboardAgentHealthHelpers layering inversion** -- Web-layer helper imported by `LoadTeams` (Ash domain). `compute_agent_health/2` should move to Fleet domain.
2. **dashboard_live.ex still 887 lines** -- More Phase 5 inline handlers, node_selected, slideout logic could be extracted. Target: 200-300 lines.
3. **Build lock contention** -- Phoenix dev server holds build lock; `mix compile` from CLI waits indefinitely.

### Architecture
- Phoenix LiveView on port 4005
- Event-driven: hooks -> POST /api/events -> EventBuffer ETS + PubSub -> LiveView
- **3 message paths (all through Gateway)**: Dashboard (Operator.send), Hook intercept (EventController), MCP (AgentTools.Inbox)
- **AgentRegistry**: ETS-backed, identity merge via CWD correlation, qualified IDs, sweep on heartbeat
- **Tmux delivery**: `set-buffer` + `paste-buffer` (no temp files)
- Ash domains: Fleet (Team, Agent), Activity (Message, Task, Error) -- all `Ash.DataLayer.Simple`

### Key Files Modified This Session
| File | Change |
|------|--------|
| `lib/observatory/gateway/agent_registry.ex` | Identity merge: find_canonical_entry, correlate_by_cwd, maybe_absorb_team_entry, is_uuid? |
| `lib/observatory/gateway/channels/tmux.ex` | deliver/2 uses set-buffer+paste-buffer instead of cat temp file |
| `lib/observatory_web/live/dashboard_live.ex` | Imported SessionControlHandlers+TmuxHandlers, simplified delegations |
| `lib/observatory_web/live/dashboard_tmux_handlers.ex` | NEW -- extracted tmux event handlers |
