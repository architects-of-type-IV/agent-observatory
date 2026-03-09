# ICHOR IV (formerly Observatory) - Handoff

## Current Status: Agent Lifecycle Management Fixed (2026-03-09)

### Just Completed

**Agent Lifecycle Closed-Loop**
- Audited all agent lifecycle paths, found 6 gaps where ghosts leaked
- `AgentProcess.terminate/2` is now the single cleanup point: kills tmux backend, removes from AgentRegistry, purges EventBuffer events, broadcasts lifecycle event
- `SessionEnd` hook now terminates the BEAM process (was only marking ETS as ended)
- `Sweep.run` now does full sweep: terminates BEAM processes + kills tmux + cleans all registries (was only deleting ETS rows)
- `AgentSpawner.stop_agent` now cleans registry + eventbuffer (was only stopping process + tmux)
- Sweep also catches orphan BEAM processes with no ETS/event backing

**Fleet UI Improvements**
- Standalone agents grouped by project (same pattern as teams, using `Path.basename(cwd)`)
- Ghost detection: agents with `event_count == 0` tagged with red GHOST badge, dimmed, strikethrough
- Operator agent hidden from fleet list (internal system entry)
- `tmux:obs` (infrastructure session) filtered from agent list via `TmuxDiscovery.infrastructure_session?/1`
- Shutdown button uses full `session_id` (was using short name that didn't match ETS key)
- Shutdown clears `selected_command_agent` for instant UI feedback
- Detail panel shows `(ghost)` status indicator
- Role badges shown on standalone agent rows

**Sweep Rewrite (Idiomatic Elixir)**
- Eliminated all `if`/`unless` -- pure pattern matching + `case` + `with` chains
- `DateTime.compare/2` instead of `<` on structs
- `full_sweep/1` as single sweep action (process + tmux + eventbuffer + ETS)
- `terminate_process/1` uses `with` chain: supervisor first, `GenServer.stop` fallback

### Previously Completed
- Full CSS tokenization (1,200+ refs migrated)
- Archon HUD + Chat + Memories integration
- BEAM-native fleet foundation
- DashboardLive dispatch/3 refactor
- Legacy module elimination (Mailbox, CommandQueue, TeamWatcher)

### .env Setup
- `ANTHROPIC_API_KEY` in `.env` at project root
- Not auto-loaded -- `source .env` before `mix phx.server`

### Build Status
`mix compile --warnings-as-errors` -- CLEAN

### Key Architecture Decision
**AgentProcess.terminate/2 is the single lifecycle reconciliation point.** All cleanup paths (shutdown, SessionEnd, sweep, spawner stop) ultimately terminate the AgentProcess, which triggers `terminate/2` to cascade cleanup. Belt-and-suspenders explicit cleanup calls exist in callers but `terminate/2` is the guarantee.

### Next Steps
1. **Theme switcher UI**: Add toggle button in dashboard header
2. **Rename codebase**: Observatory -> ICHOR IV (incremental, task 31)

### Memories Server
- Running on port 4000 (must be running for Archon memory tools)
- Requires Docker: postgres (port 5434) + falkordb (port 6379)
