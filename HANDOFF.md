# ICHOR IV - Handoff

## Current Status: Fleet Identity + Agent Naming Fixes (2026-03-10)

### Just Completed

**Agent Identity Overhaul -- 3 root causes fixed**

1. **`short_id` UUID-aware**: All 20+ `String.slice(x, 0, 8)` sites replaced with `AgentEntry.short_id/1` which uses binary pattern match to detect UUIDs. UUIDs truncated to 8 chars; human-readable names (like tmux session names) pass through unchanged. Fixes "obs-agen" truncation of "obs-agent-9725".

2. **Agent naming: never use `Path.basename(cwd)`**: `derive_display_name/3` in LoadAgents uses tmux session name or short UUID, never the project directory. `build_agent_name_map` in feed helpers follows the same rule. Fixes "observatory" appearing as agent name instead of UUID/tmux name.

3. **EventBuffer canonical session_id**: `resolve_session_id/2` now uses tmux_session as canonical ID unconditionally when present. No BEAM process alive check (was a race condition -- events arriving before TmuxDiscovery created the process got stored under UUID). Fixes duplicate agent entries and empty feed for tmux agents.

**Code quality sweep (3 review agents)**
- Removed dead `rewrite_tmux_session/2` from EventBuffer
- Removed unreachable clause in `protocol_components.ex`
- Replaced `Ecto.UUID.cast` with binary pattern match in `uuid?/1` (zero allocation)
- Moved ghost detection out of template (uses `:status` field instead of per-agent Registry lookups)
- Consolidated `maybe_put/3` in `agent_tools/spawn.ex` to shared `MapHelpers`
- Fixed missed `Path.basename(cwd)` in `swarm_handlers.ex`

**Other fixes from prior session (carried over)**
- AgentMonitor: false crash detection fixed (checks BEAM + tmux liveness before declaring crash)
- TmuxDiscovery: rewritten as continuous BEAM invariant enforcer (every tmux session gets AgentProcess)
- Ghost detection: requires no events AND no tmux AND ended/unknown status
- `infrastructure_session?/1`: only "obs" and numeric-only sessions are infrastructure
- Added InstructionsLoaded, ConfigChange, TeammateIdle hook events to settings.json
- Renamed send_event.sh env vars from OBSERVATORY to ICHOR

### Build Status
`mix compile --warnings-as-errors` -- CLEAN

### Pending / Next
- **Idle vs zombie visual distinction** (task 57)
- **Live test spawn_agent MCP tool** (task 58)
- **Archon CSS tokenization**: archon-* classes still use hardcoded rgba()
- **Hook script directory rename**: `~/.claude/hooks/observatory/` should be `~/.claude/hooks/ichor/`
- **TeamSync dead code**: listens for `{:teams_updated, teams}` but PubSub sends `{:tasks_updated, team_name}` -- never fires

### Key Architecture Decisions
- **tmux session name IS the canonical ID** for agents running in tmux. No BEAM process check needed.
- **Agent name is NOT the project directory**. Project name goes in `:project` field.
- **`AgentEntry.short_id/1`** is the single source of truth for display abbreviation.
- **`AgentEntry.uuid?/1`** uses binary pattern match (36 chars, dashes at positions 8/13/18/23).

### Runtime Notes
- Port 4005
- `~/.ichor/tmux/obs.sock` -- tmux socket path
- `~/.observatory/tmux/obs.sock` -- dead leftover from rename (user will kill)
- Memories server on port 4000 (must be running for Archon memory tools)
