# ICHOR IV (formerly Observatory) - Handoff

## Current Status: BEAM-Native Fleet + Elixir Style Guide Refactor (2026-03-08)

### Just Completed: Style Guide Refactor + Domain Audit

Refactored the BEAM-native fleet modules per the Elixir style guide:
- **Split `agent_process.ex`** (302 -> 229 lines): Extracted `AgentProcess.Delivery` (76 lines) for message normalization + backend dispatch. Pure, stateless module.
- **Added `@doc`/`@spec`** to all public functions across AgentProcess (11), TeamSupervisor (7), FleetSupervisor (5), Delivery (3)
- **Added `@spec`** to all private functions (without `@doc`)
- **Added `@type`** definitions: `status`, `t` on AgentProcess
- **Fixed `backend_from_channels`** in agent_registry.ex: pattern matching function heads instead of `cond`
- **Fixed Team resource**: Added `:beam` to `:source` constraint (was rejecting BEAM-supervised teams)
- **Fixed `update_registry_meta/4`** -> `update_registry/2` (was violating <=3 args rule)

### BEAM-Native Foundation (Prior This Session)
- AgentProcess GenServer, TeamSupervisor DynamicSupervisor, FleetSupervisor
- Two Elixir.Registry instances (ProcessRegistry, TeamRegistry)
- `ensure_agent_process` bridge in AgentRegistry.register_from_event
- Operator.send tries native delivery first
- AgentSpawner creates both tmux + BEAM process
- LoadAgents/LoadTeams merge BEAM processes into Ash read layer
- AgentTools.Inbox reads from AgentProcess.get_unread first

### ADRs Written
- ADR-001: Vendor-agnostic fleet control (channel registry, SSH, pane monitor, hierarchy)
- ADR-002: ICHOR IV identity and vision (Architect -> Archon -> Fleets -> Agents)
- ADR-023: BEAM-native agent processes (GenServer + Registry replacing ETS)
- ADR-024: Team supervision trees (DynamicSupervisor replacing TeamWatcher)
- ADR-025: Native BEAM messaging (single path replacing 5 messaging paths)

### Next: Ash Domain Model Redesign (ADR-001 + ADR-002 = the goal)

The user confirmed ADR-001 and ADR-002 are THE goal. Current Ash domain model has Fleet as read-only. Need to:

1. **Add generic actions to Fleet.Agent**: :spawn, :pause, :resume, :terminate, :send_message, :update_instructions -- each delegates to GenServer layer
2. **Add generic actions to Fleet.Team**: :create_team, :disband, :spawn_member -- delegates to DynamicSupervisor
3. **Add code interfaces**: `Fleet.Agent.spawn!/1`, `Fleet.Agent.pause!/1`, etc.
4. **Rewire AgentTools.Inbox** to use Fleet code interfaces instead of raw GenServer calls
5. **Eliminate legacy layers**: CommandQueue, Mailbox ETS, TeamWatcher disk polling
6. **Archon as permanent agent**: Operator module renamed/refactored to Archon

### Architecture Summary

| Layer | Old (still running) | New (BEAM-native) |
|-------|-------|-------|
| Agent identity | ETS row in AgentRegistry | GenServer PID in Fleet.ProcessRegistry |
| Team tracking | TeamWatcher polls ~/.claude/teams/ | TeamSupervisor (DynamicSupervisor) |
| Messaging | Mailbox ETS + CommandQueue disk | AgentProcess.send_message/2 |
| Discovery | AgentRegistry.list_all + dedup | Registry.lookup/select |
| Lifecycle | Heartbeat sweep marks stale | Supervisor restart strategies + monitors |
| Transport | Router iterates channels | AgentProcess delegates to backend |
| Ash API | Read-only (preparations) | Read + Write (generic actions) |

### Build Status
`mix compile --warnings-as-errors` clean.
