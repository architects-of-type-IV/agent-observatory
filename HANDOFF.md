# ICHOR IV - Handoff

## Current Status: HEXAGONAL REORG COMPLETE (2026-03-25)

156 .ex files. Build clean. Zero tests.

### Hexagonal Architecture (current state)

```
lib/ichor/
  factory/          # Ash domain: Pipeline, Project, PipelineTask + workers (37 files)
  workshop/         # Ash domain: Agent, Team, Prompt + presets (27 files)
  signals/          # Ash domain + ADR-026 GenStage pipeline (20 files)
  settings/         # Ash domain: SettingsProject (4 files)
  archon/           # Ash domain: system governor (5 files)
  events/           # Ash domain: StoredEvent + Ingress (4 files)
  fleet/            # OTP processes: AgentProcess, Supervisor, TeamSupervisor (9 files)
  orchestration/    # Use cases: AgentLaunch, TeamLaunch, Registration, Cleanup, TeamSpec (6 files)
  infrastructure/   # I/O boundary: Tmux, webhooks, memories, host_registry (19 files)
  projector/        # Signal subscribers (13 files)
  signal.ex         # use Ichor.Signal macro
  + other root modules (application.ex, discovery.ex, etc.)
```

### Session Summary

**Deep cleanup**: -4,700 lines (Mesh, GenStage remnants, Fleet domain, Plugin, tests, MemoriesBridge)
**ADR-026 pipeline**: GenStage pipeline with 3 signal modules, ActionHandler, StoredEvent+Checkpoint
**Frontend**: 9 primitive components + UI library with defdelegate, templates migrated
**HITL removed**: -1,002 lines (entire subsystem: HITLRelay, hitl/buffer.ex, hitl/session_state.ex)
**OTP fixes**: Task.Supervisor ordering, LifecycleSupervisor strategy, projector extraction
**Hexagonal reorg**: Fleet (9 files) + Orchestration (6 files) extracted from Infrastructure; CompletionHandler + TeamSpawnHandler moved to Projector/
**Docs**: 11 architecture docs updated, TREE.md + REFACTOR.md rewritten, BRAIN.md updated, supervision-tree.md + signals-domain.md + architecture.md fixed

### Infrastructure (19 files -- all I/O boundary)

Tmux (5): tmux.ex, tmux/, tmux_discovery.ex
External clients (2): memories_client.ex, webhook_adapter.ex
Ash Resources (2): operations.ex, webhook_delivery.ex
GenServer adapters (2): host_registry.ex, output_capture.ex
Pure helpers (1): channel.ex
Workers (3): workers/
Other (4): cron_scheduler.ex, plugs/, (5 files total with subdirs)

### Key Module Path Changes (hexagonal reorg)

| Old Path | New Path |
|----------|---------|
| `Infrastructure.FleetSupervisor` | `Fleet.Supervisor` |
| `Infrastructure.TeamSupervisor` | `Fleet.TeamSupervisor` |
| `Infrastructure.AgentProcess` | `Fleet.AgentProcess` |
| `Infrastructure.AgentLaunch` | `Orchestration.AgentLaunch` |
| `Infrastructure.TeamLaunch` | `Orchestration.TeamLaunch` |
| `Infrastructure.Registration` | `Orchestration.Registration` |
| `Infrastructure.Cleanup` | `Orchestration.Cleanup` |
| `Infrastructure.TeamSpec` | `Orchestration.TeamSpec` |
| `Factory.CompletionHandler` | `Projector.CompletionHandler` |
| `Workshop.TeamSpawnHandler` | `Projector.TeamSpawnHandler` |

### Open Items (architecture debt)

HIGH (correctness + principle violations):
- [ ] Extract result structs from `Infrastructure.MemoriesClient` into own files
- [ ] Fix `DashboardWorkshopHandlers` to use Workshop code_interface (not `Ash.destroy!` directly)
- [ ] Fix `WorkshopTypes` to use Workshop code_interface (not `Ash.destroy!` directly)
- [ ] Fix `ExportController` to use `Ichor.Events` domain code_interface

MEDIUM (maintainability):
- [ ] X1: EventStream fleet mutations (calls Fleet directly, should emit signal)
- [ ] X2: AgentWatchdog calls Factory.Board.update_task directly (should emit signal)
- [ ] Split `DashboardFeedHelpers` if > 300L
- [ ] `MemoryStore` GenServer: evaluate if ETS public reads can bypass GenServer serialization

LOW (cleanup):
- [ ] Remove dead `ProtocolTracker.compute_stats` command_queue fields (always return 0)
- [ ] Frontend Wave 3: Migrate templates to use <.button>, <.input> from library
- [ ] Frontend Wave 4: Extract remaining page sections

### Build Status
- `mix compile --warnings-as-errors`: CLEAN
- `mix test`: 0 tests
- Credo strict: 0 issues
- Dialyzer: clean (gen_stage PLT suppressed)
