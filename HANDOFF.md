# ICHOR IV - Handoff

## Current Status: MES Registry Consolidation IN PROGRESS (2026-03-13)

### Problem
MES agents spawn in tmux but have ZERO BEAM representation. 5 live tmux windows, 0 registered agents.
Root cause: 7 fragmented registries, agents registered in wrong supervisor, killed on RunProcess terminate.

### What Was Done This Session
1. **Created `Mes.AgentSupervisor`** -- DynamicSupervisor for MES agent processes (independent of RunProcess lifecycle)
2. **Created `Mes.MesAgentProcess`** -- GenServer per MES agent, monitors own tmux window, self-terminates when window dies, does NOT kill tmux on terminate
3. **Fixed RunProcess.terminate** -- no longer disbands team or kills tmux. RunProcess is spawner only.
4. **Fixed RunProcess.handle_call(:deadline_passed?)** -- `Map.get(state, :deadline_passed, false)` for old structs
5. **Fixed Janitor** -- checks tmux liveness before cleanup
6. **Fixed LoadAgents.filter_stale** -- agents with no liveness signals filtered as ghosts
7. **Updated TeamSpawner** -- registers under Mes.AgentSupervisor instead of Fleet.TeamSupervisor

### Current Blocker: Missing Signals in Catalog
`MesAgentProcess` uses `:mes_agent_stopped` and `:mes_agent_tmux_gone` which are NOT in Signals.Catalog.
`Catalog.lookup!/1` raises on unknown signals -> terminate crashes -> process dies uncleanly.
MUST add these signals before MES agents can work.

### Next: Single Registry Consolidation (USER DIRECTIVE)
User wants ONE `Ichor.Registry` for the entire system. Currently 5+ registries:
- Fleet.ProcessRegistry (Elixir Registry, agent GenServer naming)
- Fleet.TeamRegistry (Elixir Registry, team supervisor naming)
- Mes.Registry (Elixir Registry, RunProcess naming)
- Gateway.AgentRegistry (ETS table, dashboard display cache, 50 refs)
- :pg groups (cluster-wide)

Plan: single `Ichor.Registry` with compound keys `{:agent, id}`, `{:team, name}`, `{:run, id}`.

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN (243 files)
- Server restarted, AgentSupervisor running but 0 children (signals crash prevents registration)

### Runtime
- Port 4005, `~/.ichor/tmux/obs.sock`
- Live MES tmux: `mes-411c6115` (5 windows)
