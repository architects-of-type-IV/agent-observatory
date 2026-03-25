# ICHOR IV - Handoff

## Current Status: ARCHITECTURE REFACTOR (2026-03-25) -- DOCS UPDATED

284 .ex files. Build clean. Zero tests.

### Session Summary (massive session)

**Phase 1: Deep cleanup** (-4,700 lines)
- Mesh, GenStage remnants, Fleet domain, Signals indirection, Plugin, stale tests, MemoriesBridge

**Phase 2: ADR-026 Signal-as-Projector** (+1,750 lines net)
- Full GenStage pipeline: Ingress -> Router -> SignalProcess -> Handler
- 3 event sources: hooks (EventStream bridge), Ash (FromAsh), legacy signals (Runtime bridge)
- 3 signal modules: Agent.ToolBudget, Agent.MessageProtocol, Agent.Entropy
- ActionHandler with real HITL pause + operator notification
- StoredEvent + Checkpoint Ash resources (durable storage, async writes)
- Dashboard signal toasts
- Benchmarks: 514k-1.3M events/sec, crash recovery verified

**Phase 3: Frontend refactor** (ongoing)
- 9 primitive components extracted (agent_actions, close_button, panel_header, etc.)
- agent_detail_panel + agent_info_list extracted
- IchorWeb.UI defdelegate library with Layer 0 HTML primitives
- Templates migrated to use <.button>, <.input>, <.label>
- command_view: 526 -> 303 (-42%), dashboard_live: 692 -> 607 (-12%)

**Phase 4: OTP supervision fixes**
- Task.Supervisor moved before RuntimeSupervisor (dependency ordering)
- LifecycleSupervisor rest_for_one -> one_for_one (no causal deps)
- 3 projectors extracted from LifecycleSupervisor
- DynRunSupervisor renamed to PipelineRunSupervisor
- SSH tmux adapter trashed

**Phase 5: Architecture audit complete, reorg planned**
- 26-file infrastructure/ junk drawer fully analyzed
- Hexagonal plan: Ash domains = center + ports + adapters (Ash Resources with :none data layer)
- Application layer for orchestrators (Runner, Spawn, MesScheduler)
- Fleet/ for OTP agent processes
- Supervision tree audited, healing semantics documented

### Architectural Principles (from this session)
- Ash Domains are the ONLY entrypoints
- Ash Resources with `data_layer: :none` ARE the adapters (no separate adapter layer)
- Dependencies point inward only: Processes -> Application -> Domains
- Event = something happened, Signal = enough happened, Handler = now act
- Naming: big to small (agent.tool.budget.exhausted)
- Frontend: layered components with defdelegate library, one file per component

### Build Status
- `mix compile --warnings-as-errors`: CLEAN
- `mix test`: 0 tests

### Architecture Docs Updated (2026-03-25)
- `docs/architecture/decisions.md` -- AD-8 extended with StoredEvent; AshSqlite -> AshPostgres
- `docs/architecture/signals-domain.md` -- GenStage pipeline section added (ADR-026)
- `docs/architecture/supervision-tree.md` -- Full current tree diagram + strategy table
- `docs/architecture/2026-03-23-ichor-v2.md` -- Status updated, deleted subsystems marked, migration status table
- `docs/pages/signals.md` -- GenStage pipeline section + updated key files list
- `docs/pages/pipeline.md` -- PipelineMonitor -> ProjectDiscoveryWorker corrected
- `docs/pages/fleet.md` -- :mesh_pause legacy note added
- `docs/diagrams/architecture.md` -- Domain Boundaries diagram + Signal Flow diagram updated
- `SPECS/decisions/ADR-026-signal-as-projector.md` -- status: proposed -> implemented

### Next Steps
1. File moves (hexagonal reorg) -- move infrastructure/ files to correct layers
2. Convert external API modules to Ash Resources with :none data layer (Tmux, Memories, Webhooks)
3. Fresh tests against signal pipeline + Ash domain APIs
4. Continue frontend component extraction (workshop_view, detail_panel, signals_view)
