# ICHOR IV - Handoff

## Current Status: Fleet Observability + MCP Spawn Tool (2026-03-09)

### Just Completed

**Subagent Hierarchy Fix + Clickable Subagents**
- Rewrote `build_subagent_map` in LoadAgents to use PreToolUse/PostToolUse "Agent"/"Task" events (rich metadata: description, subagent_type, name) instead of SubagentStart (nil subagent_id, no metadata)
- Subagents are metadata on the parent agent, not separate Fleet.Agent entries
- Clickable subagent rows in fleet tree with `phx-click="select_subagent"` -> detail panel showing type, parent (clickable), description, tool_use_id, started_at
- Added `subagents` attribute to Fleet.Agent (`:array, :map`, default `[]`)

**NudgeEscalator Fixes**
- Increased thresholds: stale 600s, nudge interval 300s (was 120s/60s)
- Auto-unpause on activity resume: new events trigger HITLRelay.unpause when level >= 2
- Non-tmux agents capped at escalation level 0 (no tmux nudge or HITL pause)
- Added `/api/debug/hitl-clear` endpoint for bulk unpause

**spawn_agent MCP Tool**
- `Ichor.AgentTools.Spawn` resource with `spawn_agent` and `stop_agent` actions
- Registered in AgentTools domain and MCP router tools list
- Delegates to `Ichor.AgentSpawner.spawn_agent/1`
- 8 params: prompt, capability, model, name, team_name, cwd, file_scope, extra_instructions

### Previously Completed
- Codebase rename: Observatory -> Ichor (211 modules)
- Agent lifecycle closed-loop (6 gaps fixed)
- Full CSS tokenization (1,200+ refs migrated)
- Archon HUD + Chat + Memories integration
- BEAM-native fleet foundation
- DashboardLive dispatch/3 refactor
- Legacy module elimination (Mailbox, CommandQueue, TeamWatcher)

### Pending / Next
- **Idle vs zombie visual distinction**: User wants clear differentiation. Fleet.Agent status has `[:active, :idle, :ended]` -- may need `:zombie` status or visual treatment
- **Live test spawn_agent MCP tool**: Registered and verified via tools/list, no live spawn test yet
- **Archon CSS tokenization**: archon-* classes still use hardcoded rgba()

### .env Setup
- `ANTHROPIC_API_KEY` in `.env` at project root
- Not auto-loaded -- `source .env` before `mix phx.server`

### Build Status
`mix compile --warnings-as-errors` -- CLEAN

### Key Architecture Decisions
- **Module prefix**: `Ichor` (not `IchorIV`). Dashboard title is "ICHOR IV".
- **AgentProcess.terminate/2** is the single lifecycle reconciliation point.
- **Subagents are decorative metadata** on parents, not independent Fleet.Agent entries.
- **No theme switcher UI** -- user decided against on-demand theme switching.

### Runtime Notes
- Port 4005
- `~/.ichor/tmux/obs.sock` -- tmux socket path
- Memories server on port 4000 (must be running for Archon memory tools)
- Docker: postgres (5434) + falkordb (6379) for Memories
