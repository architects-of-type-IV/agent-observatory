# Genesis Mode A Smoke Test

**Date:** 2026-03-17
**Target:** PulseMonitor (e861fbf0-21a5-480d-92c1-cafc398ca8c6, status: loaded)

## Phase 1: Component Verification (no agents spawned)

1. MCP tools -- create_adr, list_adrs, gate_check via iex against temporary genesis node
2. Script generation -- write_agent_scripts with mock data, inspect .sh and .txt files
3. Tmux + fleet registration -- create throwaway session, register agent, verify in fleet

## Phase 2: Full Pipeline Fire

4. Launch Mode A -- user clicks UI button, verify node + tmux + fleet registration
5. Monitor agent execution -- scrape tmux panes for message flow, MCP calls, errors
6. Verify results -- ADRs in DB, gate check passes, no orphaned sessions

## Exit Criteria

- All 3 ADRs in DB
- Gate check returns ready_for_define: true
- Zero crashes or unhandled errors
