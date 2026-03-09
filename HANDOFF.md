# ICHOR IV (formerly Observatory) - Handoff

## Current Status: Archon HUD Redesign + Fleet Action Fixes (2026-03-09)

### Just Completed

**Archon Type IV Sovereign HUD Redesign**
- Redesigned from full-screen opaque modal to centered 16:9 translucent glass panel
- Three tabbed views: Command (Q), Chat (W), Reference (E) -- keyboard-switchable
- Command tab: 7 quick action cards bound to keys 1-7 (agents, teams, inbox, health, sessions, recall, query) + mini activity feed
- Chat tab: full conversation view with Archon
- Reference tab: all 10 shortcodes in clickable grid
- Keyboard context: when Archon open, number keys fire shortcodes; Q/W/E switch tabs; esc/a closes
- DOM MutationObserver tracks archon open state for keyboard routing
- Visual: translucent glass (bg-black/40), amber glow, gradient edge, pulsing sigil, ONLINE status

**Fleet Control Fixes (5 issues)**
1. `agent_index` not passed to `command_view` component -- fleet sidebar always showed 0 agents
2. `shutdown_agent` only sent a message, didn't mark ended or stop AgentProcess
3. `kill_tmux_session` killed tmux but didn't remove from AgentRegistry
4. Pause/Resume didn't update `paused_sessions` MapSet immediately (waited for PubSub)
5. Focus button was dead -- `agent_slideout` assign set but no template rendered it

**New Features**
- `AgentRegistry.remove/1` -- delete agent from ETS + broadcast registry change
- Agent Focus slideout panel -- right-edge slide-over showing agent info, terminal, activity
- HITL gate Archon notification -- system-role alert auto-opens Archon when agent is paused
- System message styling in Archon chat (amber alert bubble, "alert" meta label)

### Previously Completed

**LiveView Performance Optimization (6 fixes)**
- Tiered recompute, debounced recompute, deferred mount, conditional computation

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
