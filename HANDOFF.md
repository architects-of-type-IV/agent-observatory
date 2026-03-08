# ICHOR IV (formerly Observatory) - Handoff

## Current Status: Registry Decomposition + Distribution Prep (2026-03-09)

### Just Completed

1. **Feed UI improvements** -- compacted session headers, stripped pill badges to plain text, markdown-rendered agent responses (Earmark dependency added)

2. **Launch button fix** -- `handle_launch_session` now uses `AgentSpawner.spawn_agent/1` (full pipeline: tmux + overlay + BEAM process + registry). Added `env -u CLAUDECODE` for fresh session identity.

3. **AgentRegistry decomposition** (IN PROGRESS) -- extracted 2 modules from 894-line god module:
   - `Gateway.OutputCapture` (108 lines) -- terminal output polling
   - `Gateway.TmuxDiscovery` (115 lines) -- tmux session discovery + channel wiring
   - Both are GenServers in GatewaySupervisor
   - AgentRegistry down to 767 lines, still has dead tree code to remove

### Next Steps (ordered)

1. **Remove dead tree code** -- `children/1`, `parent/1`, `chain_of_command/1`, `reparent/2` and helpers have zero external callers
2. **Distribution support** -- BEAM clustering for multi-host agent fleet:
   - Host registry (which remote servers exist)
   - AgentSpawner remote spawning via SSH
   - FleetSupervisor multi-node awareness
   - PubSub already distribution-aware

### Prior Work
- Archon domain + AgentTools refactor (2026-03-08)
- Workshop refactor + Ash-disciplined refactor (Phases 1-7)

### Remaining (backlog)
- Memories integration, Archon LLM, Archon chat UI
- Phase 8: ICHOR IV rename (deferred)

### Build Status
`mix compile --warnings-as-errors` clean.
