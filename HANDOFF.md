# ICHOR IV (formerly Observatory) - Handoff

## Current Status: BEAM-Native Agent Architecture (2026-03-08)

### Just Completed: Foundation Layer (ADR-023/024/025 Implementation)

Built the BEAM-native fleet foundation -- three new modules + supervision wiring:

**New modules:**
- `lib/observatory/fleet/agent_process.ex` -- GenServer per agent. PID = identity, process mailbox = delivery target. Registers in `Observatory.Fleet.ProcessRegistry` (Elixir.Registry). Supports pause/resume, metadata updates, instruction overlays. Backend-pluggable delivery (tmux, SSH, webhook).
- `lib/observatory/fleet/team_supervisor.ex` -- DynamicSupervisor per team. Configurable restart strategies (:one_for_one, :rest_for_one, :one_for_all). Registers in `Observatory.Fleet.TeamRegistry`. Spawns/terminates members.
- `lib/observatory/fleet/fleet_supervisor.ex` -- Top-level DynamicSupervisor. Creates teams, spawns standalone agents. Entry point for all fleet operations.

**Wired into supervision tree** (`application.ex`):
- Two `Registry` instances: `Fleet.ProcessRegistry` (agents) and `Fleet.TeamRegistry` (teams)
- `Fleet.FleetSupervisor` starts after Gateway (needs channel access)

**ADRs written:**
- ADR-023: BEAM-Native Agent Processes (GenServer + Registry replacing ETS AgentRegistry)
- ADR-024: Team Supervision Trees (DynamicSupervisor replacing TeamWatcher disk polling)
- ADR-025: Native BEAM Messaging (single path replacing 5 messaging paths)

**Build status:** `mix compile --warnings-as-errors` clean.

### Migration Path (Not Yet Done)

The new BEAM-native layer coexists with the old ETS-based layer. Both run simultaneously. Next steps to complete the migration:

1. **Wire Operator.send to AgentProcess** -- When an AgentProcess exists for a target, deliver via GenServer.cast instead of Gateway.Router.broadcast.
2. **Wire AgentSpawner to FleetSupervisor** -- `spawn_agent/1` should `FleetSupervisor.spawn_agent/1` instead of raw tmux commands.
3. **Update LoadAgents preparation** -- Read from `Fleet.ProcessRegistry` alongside EventBuffer/tmux sources.
4. **Update LoadTeams preparation** -- Read from `Fleet.TeamRegistry` alongside TeamWatcher.
5. **MCP check_inbox** -- Read from AgentProcess.get_unread instead of Mailbox ETS.
6. **Eliminate CommandQueue** -- Once all agents use AgentProcess, remove disk-based inbox.
7. **Eliminate TeamWatcher** -- Once all teams use TeamSupervisor, remove disk polling.
8. **Eliminate Mailbox** -- Once all messages route through AgentProcess, remove ETS mailbox.

### Architecture Summary

| Layer | Old (still running) | New (BEAM-native) |
|-------|-------|-------|
| Agent identity | ETS row in AgentRegistry | GenServer PID in Fleet.ProcessRegistry |
| Team tracking | TeamWatcher polls ~/.claude/teams/ | TeamSupervisor (DynamicSupervisor) |
| Messaging | Mailbox ETS + CommandQueue disk | AgentProcess.send_message/2 |
| Discovery | AgentRegistry.list_all + dedup | Registry.lookup/select |
| Lifecycle | Heartbeat sweep marks stale | Supervisor restart strategies + monitors |
| Transport | Router iterates channels | AgentProcess delegates to backend |

### Prior Work
- ADR-001: vendor-agnostic fleet control (5 steps, all complete)
- ADR-002: ICHOR IV identity and vision
- Unified agent index, cost ingestion, SSH tmux, PaneMonitor, HITL, multi-panel tmux
- See progress.txt for full history

### Open Issues
1. `ash_ai 0.5.0` SSE `{:error, :closed}` on MCP disconnect -- benign noise
2. Agent spawn UI -- no form yet
3. Codebase rename from Observatory to ICHOR IV -- not started
