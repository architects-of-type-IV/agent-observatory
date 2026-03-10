# ICHOR IV - Handoff

## Current Status: Shutdown Ghost Fix + EventBuffer Rewrite (2026-03-10)

### Just Completed

**Shutdown ghost reappearance fix -- 2 mechanisms**

Root cause: clicking Shutdown kills the tmux session, then the Claude Code SessionEnd hook fires with empty `$TMUX_SESSION` (tmux is dead). `resolve_session_id` falls back to the raw UUID, creating a ghost agent entry (e.g., `6999954d`).

1. **Session aliases**: EventBuffer caches UUID-to-tmux-session mappings in an ETS table (`@aliases`) as events flow. When a late event arrives with only the raw UUID, the alias resolves it to the canonical tmux session name.

2. **Tombstones**: `tombstone_session/1` places a 30s marker in ETS (`@tombstones`). Events resolving to a tombstoned session are silently dropped. Prevents ghost entries from SessionEnd hooks.

3. **Preserve events on shutdown**: `AgentProcess.terminate/2` and `handle_shutdown_agent` now call `tombstone_session/1` (not `remove_session/1`). Events are kept so the agent stays visible in the sidebar as ended. Only the MCP `stop_agent` tool uses full `remove_session/1`.

**EventBuffer full rewrite** -- idiomatic Elixir
- Eliminated 4 separate `ensure_*` functions -> single `ensure_ets/1` with `Enum.each`
- Pattern-matched function heads for `put_duration`, `track_tool_start`, `resolve_session_id`
- Extracted `coerce_hook_type/1` from inline logic in `build_event`
- Removed all imperative if/else mixed into declarative pipelines

**Prior session: Agent Identity Overhaul (3 root causes)**
1. `short_id` UUID-aware (20+ sites fixed)
2. Agent naming: tmux session name > short UUID, never `Path.basename(cwd)`
3. EventBuffer canonical session_id: tmux_session unconditionally

### Build Status
`mix compile --warnings-as-errors` -- CLEAN

### Pending / Next
- **Idle vs zombie visual distinction** (task 57)
- **Live test spawn_agent MCP tool** (task 58)
- **Archon CSS tokenization**: archon-* classes still use hardcoded rgba()
- **Hook script directory rename**: `~/.claude/hooks/observatory/` -> `~/.claude/hooks/ichor/`
- **TeamSync dead code**: listens for `{:teams_updated, teams}` but PubSub sends `{:tasks_updated, team_name}` -- never fires
- **`Ichor.Fleet` Spark DSL error**: transient crash during hot reload. Confirm it doesn't persist after fresh restart.

### Key Architecture Decisions
- **tmux session name IS the canonical ID** for agents running in tmux
- **Agent name is NOT the project directory**
- **`AgentEntry.short_id/1`** is the single source of truth for display abbreviation
- **Shutdown preserves events** -- agents stay visible as ended, tombstone blocks ghost UUIDs
- **No filtering of idle sessions** -- sidebar shows all sessions, idle sorted to bottom

### Runtime Notes
- Port 4005
- `~/.ichor/tmux/obs.sock` -- tmux socket path
- Memories server on port 4000 (must be running for Archon memory tools)
