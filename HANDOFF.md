# ICHOR IV - Handoff

## Current Status: os_pid tracking + dashboard mount fix (2026-03-10)

### Just Completed

**1. os_pid tracking -- capture Claude process PID**

Root cause investigation: agent `226ec980` showed as closed session but system didn't detect it. Non-tmux agents have no way to detect process death.

Added `os_pid` field end-to-end:
- **Hook** (`~/.claude/hooks/observatory/send_event.sh`): walks PID tree from `$$` upward to find `claude` process, falls back to `$PPID`. Sends as integer in JSON envelope.
- **EventController**: extracts `os_pid` from params, coerces to integer via `Integer.parse`
- **EventBuffer**: stores `os_pid` on every event struct
- **AgentRegistry.AgentEntry**: default map includes `os_pid: nil`
- **AgentRegistry.EventHandler**: `apply_event` updates `os_pid` from incoming events
- **LoadAgents**: extracts most recent `os_pid` from events, attaches to Fleet.Agent, merges from registry
- **Fleet.Agent**: new `:os_pid` integer attribute

Not yet wired into UI or liveness detection. Future use: `kill -0 <pid>` for alive check, tmux pane_pid tree walking.

**2. Dashboard mount event seed -- agents visible on page load**

Root cause: non-tmux agents invisible after page refresh. `assigns.events` starts empty on mount. `FQ.active_sessions` derives sessions from `assigns.events`, so no events = no sessions. Tmux-only agents were fine (tmux scan path). Non-tmux agents only appeared after their next hook event.

Fix: `EventBuffer.latest_per_session/0` -- single-pass `:ets.foldl` returning one event per session. Seeds `assigns.events` on `:load_data` mount. PubSub stream handles everything after. Memory-efficient: accumulator is just `%{session_id => event}`, no intermediate lists.

### Build Status
`mix compile --warnings-as-errors` -- CLEAN

### Pending / Next
- **Wire os_pid into liveness detection** -- use `kill -0` or `System.cmd` to check if Claude process is alive
- **Idle vs zombie visual distinction** (task 57)
- **Live test spawn_agent MCP tool** (task 58)
- **Archon CSS tokenization**: archon-* classes still use hardcoded rgba()
- **Hook script directory rename**: `~/.claude/hooks/observatory/` -> `~/.claude/hooks/ichor/`

### Key Architecture Decisions
- **`os_pid`** is the single name for the OS process ID everywhere (hook, controller, buffer, registry, agent)
- **Dashboard mount seeds 1 event per session** -- not bulk load. Stream handles the rest.
- **`:ets.foldl`** for memory-efficient single-pass aggregation over ETS
- **tmux session name IS the canonical ID** for agents running in tmux
- **Shutdown preserves events** -- agents stay visible as ended, tombstone blocks ghost UUIDs

### Runtime Notes
- Port 4005
- `~/.ichor/tmux/obs.sock` -- tmux socket path
- Memories server on port 4000 (must be running for Archon memory tools)
