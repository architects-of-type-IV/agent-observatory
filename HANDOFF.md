# ICHOR IV (formerly Observatory) - Handoff

## Current Status: LiveView Performance Optimization (2026-03-09)

### Just Completed

**LiveView Performance Optimization (6 fixes)**

Audited dashboard LiveView against common Phoenix LiveView performance anti-patterns. Applied 6 optimizations:

1. **Tiered recompute** -- Split `recompute/1` into full (Ash+SQL queries) and `recompute_view/1` (display-only, no queries). UI toggles and selections skip all data queries.
2. **Debounced recompute** -- PubSub events (new_event, registry_changed, etc.) schedule a single recompute after 100ms instead of firing immediately. Multiple events within the window coalesce.
3. **Eliminated double recompute** -- `{:swarm_state}` was re-broadcasting events:stream, causing 2 full recomputes per hook event. Now assigns only, no recompute.
4. **Deferred mount** -- Static render gets lightweight defaults. `send(self(), :load_data)` triggers full data load + `seed_gateway_assigns` only after WebSocket connects.
5. **Conditional computation** -- analytics/timeline only computed when activity tab is active. Feed groups only on command/activity view. Cost data (3 SQL queries) only on forensic/control view.
6. **Eliminated redundant queries** -- `load_messages/2` reuses the already-fetched `messages` list instead of calling `Activity.Message.recent!()` a second time.

**Events removed from recompute entirely:**
- `{:swarm_state}` -- assign only (was double-recomputing)
- `{:hitl}` -- just refreshes paused_sessions assign
- Nudge/gate events -- notifications only, no data changed
- Gateway messages -- `handle_gateway_info` already updates its own assigns
- UI toggles (toggle_shortcuts_help, toggle_create_task_modal, etc.)
- Selection events (select_event, select_task, select_agent, close_detail)

### Previously Completed

**Fleet Consistency Rewire + Legacy Elimination (tasks 42, 51)**
- All external callers rewired to Fleet code interfaces
- Mailbox, CommandQueue, TeamWatcher deleted

**DashboardLive refactor: 594 -> 164 lines (dispatch/3 pattern)**

### .env Setup
- `ANTHROPIC_API_KEY` in `.env` at project root
- Not auto-loaded -- `source .env` before `mix phx.server`

### Build Status
`mix compile --warnings-as-errors` -- CLEAN

### Next Steps
1. **Streams** (deferred): Convert events list to LiveView streams for render perf
2. **LiveComponents** (deferred): Isolate fleet tree, feed, inspector as stateful components
3. **Task 8** (pending, low priority): Non-blocking event pipeline validation
4. **Task 31** (pending, low priority): Rename codebase to ICHOR IV

### Memories Server
- Running on port 4000 (must be running for Archon memory tools)
- Requires Docker: postgres (port 5434) + falkordb (port 6379)
- ONNX models on external drive: `/Volumes/T5/models/ONNX`
