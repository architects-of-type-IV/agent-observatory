# Observatory - Handoff

## Current Status: Code Quality Hardening (2026-03-08)

### Just Completed (/simplify review)
- **ETS scan optimization** -- `correlate_by_cwd` pre-builds cwd index before member loop (O(M*N) -> O(N)). `maybe_absorb_team_entry` uses `ets.match_object` instead of `tab2list` on every hook event. `poll_tmux_sessions` reuses `all_entries` instead of redundant second scan.
- **`broadcast_registry_update`** -- Now sends `:registry_changed` signal instead of materializing full agent table via `list_all()` (nobody subscribes yet).
- **`is_uuid?` replaced** -- Hand-rolled UUID validator replaced with `Ecto.UUID.cast/1`.
- **Tmux API unification** -- New `Tmux.run_command/1` public API. DashboardTmuxHandlers no longer bypasses `try_tmux` via direct `System.cmd` calls. All tmux ops go through multi-server fallback.
- **`server_arg_sets` cached** -- 5s TTL via `Process.put/get`. Eliminates repeated `File.exists?` stat calls (was 3x per deliver, plus polling).
- **Named tmux buffers** -- `deliver/2` uses `obs-{unique_int}` named buffers with `-d` auto-delete. Prevents concurrent delivery corruption.

### Prior Work (same day)
- Identity merge in AgentRegistry (CWD correlation, canonical UUID keys)
- Ash domain refactor steps 7-9 (imported handlers, extracted DashboardTmuxHandlers)
- Tmux deliver fix (set-buffer+paste-buffer, no temp files)
- Heartbeat tmux filter (skip :heartbeat/:system from tmux delivery)
- Debug endpoints, EventController Gateway unification, qualified naming, stale sweep

### Open Issues
1. **DashboardAgentHealthHelpers layering inversion** -- Web-layer helper imported by `LoadTeams` (Ash domain). `compute_agent_health/2` should move to Fleet domain.
2. **dashboard_live.ex still 887 lines** -- More Phase 5 inline handlers, node_selected, slideout logic could be extracted. Target: 200-300 lines.
3. **Build lock contention** -- Phoenix dev server holds build lock; `mix compile` from CLI waits indefinitely.

### Architecture
- Phoenix LiveView on port 4005
- Event-driven: hooks -> POST /api/events -> EventBuffer ETS + PubSub -> LiveView
- **3 message paths (all through Gateway)**: Dashboard (Operator.send), Hook intercept (EventController), MCP (AgentTools.Inbox)
- **AgentRegistry**: ETS-backed, identity merge via CWD correlation, qualified IDs, sweep on heartbeat. Broadcasts `:registry_changed` signal (not full table).
- **Tmux**: `Tmux.run_command/1` for all ops, named buffers, `server_arg_sets` cached 5s TTL
- Ash domains: Fleet (Team, Agent), Activity (Message, Task, Error) -- all `Ash.DataLayer.Simple`

### Key Files Modified This Session
| File | Change |
|------|--------|
| `lib/observatory/gateway/agent_registry.ex` | ETS scan optimization, `:registry_changed` signal, `Ecto.UUID.cast`, pre-built cwd index |
| `lib/observatory/gateway/channels/tmux.ex` | `run_command/1` public API, `server_arg_sets` cache, named buffers |
| `lib/observatory_web/live/dashboard_live.ex` | Imported SessionControlHandlers+TmuxHandlers, simplified delegations |
| `lib/observatory_web/live/dashboard_tmux_handlers.ex` | Uses `Tmux.run_command/1` instead of direct `System.cmd` |
