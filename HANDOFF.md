# ICHOR IV - Handoff

## Current Status: Fleet GC + Archon Control + /stream page (2026-03-10)

### Just Completed

**1. Liveness-first GC sweep**
- Rewrote `AgentRegistry.Sweep` to use observable facts: `kill -0` for PID, tmux session list membership
- Safe-by-default: `live_tmux_sessions/0` returns `{:ok, MapSet} | :error` -- on tmux failure, keep agents (never false-sweep)
- Reduced `@ended_ttl_seconds` 1800->60, `@stale_ttl_seconds` 3600->600
- Heartbeat sweep cadence 5min->1min (every 12 beats)
- `LoadAgents.filter_stale/3`: display-layer filter for ended/dead-PID/dead-tmux/idle>10min agents

**2. Archon advanced system control**
- `Archon.Tools.Control` (5 actions): spawn_agent, stop_agent, pause_agent, resume_agent, sweep
- `Archon.Tools.Events` (2 actions): agent_events, fleet_tasks
- 7 new tools registered in Archon.Tools domain
- Chat system prompt updated with full capability list + slash commands

**3. /stream page -- PubSub topic catalog + live feed**
- `Ichor.Stream.TopicCatalog`: 30 PubSub topics cataloged with category/shapes/broadcasters/subscribers
- `Ichor.Stream.StreamBuffer`: GenServer subscribing all static topics, 500-event ring buffer, re-broadcasts on `"stream:feed"`
- `IchorWeb.StreamComponents`: two-panel layout (topic catalog + live feed), filter/pause/clear
- Nav icon (radio wave SVG) added to dashboard, route via `?view=stream`
- `StreamAutoScroll` JS hook

### Build Status
`mix compile --warnings-as-errors` -- CLEAN

### Pending / Next
- **Archon.Watchdog** -- tiered rules + LLM escalation (Option C from analysis)
- **Stream page sidebar** -- user noted uncertainty about sidebar layout
- Wire os_pid into liveness detection (kill -0)
- Archon CSS tokenization: archon-* classes still use hardcoded rgba()

### Key Architecture Decisions
- **Observable liveness > hook dependency**: sweep uses PID+tmux checks, not SessionEnd hooks
- **Safe-by-default GC**: `{:ok, set} | :error` pattern prevents false-sweep on tmux failure
- **TopicCatalog**: compile-time module attribute, source of truth for /stream and future Watchdog
- **StreamBuffer**: subscribe-classify-buffer-rebroadcast pattern. ETS ring buffer, 500 events max.

### Runtime Notes
- Port 4005, `~/.ichor/tmux/obs.sock`
- Memories server on port 4000 (must be running for Archon memory tools)
