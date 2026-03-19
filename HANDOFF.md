# ICHOR IV - Handoff

## Current Status: Domain Centralization + Signal Feed Refactor (2026-03-19)

### Session Summary

Coordinator-driven session. All code work delegated to ash-elixir-expert agents. Codex (GPT-5.4) consulted for signal feed architecture. Major changes across domains, signals, module consolidation, and LiveView streaming.

### Completed This Session

1. **Build fix** -- `consolidate_protocols: Mix.env() != :dev` (3 Ash Inspect warnings)
2. **Genesis domain centralization** -- 27 new domain functions for 9 sub-resources, 3 agent tools rewired
3. **Workshop domain centralization** -- 6 new domain functions, Persistence module rewired
4. **MES domain centralization** -- 3 new domain functions (pick_up_project, projects_by_status, projects_by_status!), handler + archon tools rewired
5. **Workshop delegation chain collapse** -- 4-hop chain reduced to direct domain calls, dead defdelegate removed from WorkshopPresets
6. **Fleet RuntimeHooks/Runtime removal** -- 2 wrapper modules deleted, 22 call sites rewired to actual implementations
7. **Signal livefeed refactor (codex-designed):**
   - Buffer stores `{seq, %Message{}}` raw tuples (removed EntryFormatter from hot path)
   - LiveView uses `stream/stream_insert` with `at: 0, limit: 200` (no list assigns)
   - PubSub topic: `"signals:feed"` with `{:signal, seq, message}` shape
   - 10 new per-category renderer components (agent, core, gateway, genesis, dag, mes, monitoring, fallback + primitives + dispatcher)
8. **AgentWatchdog merge** -- 4 GenServers (heartbeat, agent_monitor, nudge_escalator, pane_monitor) -> 1 GenServer + 3 pure helpers (EventState, NudgePolicy, PaneParser). Fixed inverted `return_if_no_team` bug.
9. **Module consolidation** -- Deleted archon.ex (empty domain), mailer.ex (dead stub). Moved event_janitor -> events/janitor.ex, heartbeat -> signals/heartbeat.ex
10. **Ash.Type.Enum extraction** -- 5 HIGH priority enums created (HookEventType, AgentStatus, HealthStatus, NodeStatus, ProjectStatus), 6 resource attributes updated
11. **Stale tmux agents cleaned** -- Killed disconnected genesis team + researcher sessions

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN
- `mix credo --strict` -- CLEAN (0 issues)
- File count: 398 (was 387, net +11 from new renderer/enum/watchdog files minus deleted modules)

### What's Next (Priority Order)
1. Ash.Type.Enum extraction -- 6 remaining MEDIUM/LOW candidates (JobPriority, JobStatus, RunStatus, RunSource, SessionStatus, WorkStatus)
2. Comprehensive Ash DSL audit against `mix usage_rules.search_docs`
3. @spec coverage on remaining public functions
4. E2E test: Build PulseMonitor with boundary enforcement
5. Boundary violation fixes (web helpers imported by core)
6. EntryFormatter -- decide: keep for export/debug, or delete entirely
