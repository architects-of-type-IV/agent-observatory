# ICHOR IV - Handoff

## Current Status: HEXAGONAL REORG IN PROGRESS (2026-03-25)

277 .ex files. Build clean. Zero tests.

### Hexagonal Architecture (current state)

```
lib/ichor/
  factory/          # Ash domain: Pipeline, Project, PipelineTask + workers
  workshop/         # Ash domain: Agent, Team, Prompt + presets
  signals/          # Ash domain + ADR-026 GenStage pipeline
  settings/         # Ash domain: SettingsProject
  archon/           # Ash domain: system governor
  events/           # Ash domain: StoredEvent + Ingress
  fleet/            # OTP processes: AgentProcess, Supervisor, TeamSupervisor (9 files)
  orchestration/    # Use cases: AgentLaunch, TeamLaunch, Registration, Cleanup, TeamSpec (6 files)
  infrastructure/   # I/O boundary: Tmux, webhooks, memories, host_registry (19 files)
  projector/        # Signal subscribers (10 files)
  signal.ex         # use Ichor.Signal macro
```

### Session Summary

**Deep cleanup**: -4,700 lines (Mesh, GenStage remnants, Fleet domain, Plugin, tests, MemoriesBridge)
**ADR-026 pipeline**: GenStage pipeline with 3 signal modules, ActionHandler, StoredEvent+Checkpoint
**Frontend**: 9 primitive components + UI library with defdelegate, templates migrated
**HITL removed**: -1,002 lines (entire subsystem)
**OTP fixes**: Task.Supervisor ordering, LifecycleSupervisor strategy, projector extraction
**Hexagonal reorg**: Fleet (9 files) + Orchestration (6 files) extracted from infrastructure
**Docs**: 11 architecture docs updated, TREE.md + REFACTOR.md rewritten, static analysis fixed

### Infrastructure (19 files remaining -- all I/O boundary)

Tmux (5): tmux.ex, tmux/, tmux_discovery.ex
External clients (2): memories_client.ex, webhook_adapter.ex
Ash Resources (2): operations.ex, webhook_delivery.ex
GenServer adapters (2): host_registry.ex, output_capture.ex
Pure helpers (2): ansi_utils.ex, channel.ex
Workers (3): workers/
Other (2): cron_scheduler.ex, plugs/

### Build Status
- `mix compile --warnings-as-errors`: CLEAN
- `mix test`: 0 tests
