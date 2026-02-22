# Observatory - Handoff

## Current Status: Dashboard-to-Backend Wiring COMPLETE (2026-02-22)

### Just Completed: Live Topology Pipeline + Gateway Handlers

**286 tests, 0 failures, zero warnings.**

Wired Phase 5 dashboard views to live backend data. Full end-to-end pipeline now active:

| Change | File | What |
|--------|------|------|
| Supervision | application.ex | Added CausalDAG + TopologyBuilder to supervisor tree |
| DAG feeding | event_bridge.ex | Converts hook events to CausalDAG nodes, tracks parent chain per session |
| Fleet topology | dashboard_gateway_handlers.ex | Pushes topology updates to fleet canvas via push_event |
| Session DAG | dashboard_gateway_handlers.ex | Per-session DAG subscription, push_event for drill-down |
| Fleet canvas | fleet_command_components.ex | Real TopologyMap hook + canvas (was placeholder) |
| Session canvas | session_cluster_components.ex | Real TopologyMap hook + canvas (was placeholder) |
| JS configurable | topology_map.js | data-event attribute for dual instances (fleet + session) |
| Dashboard routing | dashboard_live.ex | handle_info for topology + DAG delta messages |
| Test isolation | causal_dag.ex | reset/0 API for test cleanup (avoids start_supervised conflict) |

Also created DashboardGatewayHandlers module (prior session) with:
- PubSub subscriptions to gateway:messages, gateway:topology, gateway:entropy_alerts, gateway:dlq
- DecisionLog stream processing (throughput, cost, latency, scratchpad)
- EventBridge GenServer bridging events:stream into gateway pipeline + CausalDAG
- EntropyTracker fallback fix (safe_call pattern)
- Dead stub removal (dashboard_session_helpers stubs)

### Previous: Phase 5 Hypervisor UI (6 tasks, 4 waves, ~18 min)

DAG team: `dag-1771779126` (archived via GC)

| Task | Subject | Worker | Model | Tests |
|------|---------|--------|-------|-------|
| 1 | Six-View Navigation Shell | worker-1 | opus | 8 |
| 2 | Fleet Command View + all dashboard_live.ex wiring | worker-2 | sonnet | 3 |
| 3 | Session Cluster + Registry Views | worker-3 | sonnet | 6 |
| 4 | Scheduler + Forensic Inspector Views | worker-4 | sonnet | 13 |
| 5 | God Mode View + Kill Switch + CSS | worker-5 | sonnet | 7 |
| 6 | Final validation (full suite) | worker-6 | haiku | 233 |
| fix | Registry test assertion fix | worker-fix | haiku | - |

### Waves
- Wave 1: Task 1 (opus anchor, defines view_mode contract + 6 component stubs)
- Wave 2: Tasks 2, 3, 5 (parallel sonnet workers; task 2 owned dashboard_live.ex exclusively)
- Wave 3: Task 4 (sonnet, blocked by task 3)
- Wave 4: Task 6 (haiku verification)

### New Files Created (12)
| File | Purpose |
|------|---------|
| `lib/observatory_web/components/fleet_command_components.ex` | Six-panel layout: mesh topology, throughput, cost heatmap, health, latency, mTLS |
| `lib/observatory_web/components/session_cluster_components.ex` | Session list with entropy filter, drill-down (DAG, scratchpad, HITL), collapsible sub-panels |
| `lib/observatory_web/components/registry_components.ex` | Sortable capability directory, routing logic manager with weight validation |
| `lib/observatory_web/components/scheduler_components.ex` | Cron job dashboard, DLQ with retry, heartbeat monitor zombie list |
| `lib/observatory_web/components/forensic_components.ex` | Message archive search, cost attribution, security log, policy engine |
| `lib/observatory_web/components/god_mode_components.ex` | Kill switch double-confirm state machine, danger-zone CSS, global instructions |
| `test/observatory_web/live/dashboard_live_test.exs` | 8 tests for navigation shell |
| `test/observatory_web/live/fleet_command_test.exs` | 3 tests for fleet command panels |
| `test/observatory_web/live/session_cluster_test.exs` | 6 tests for session cluster + registry |
| `test/observatory_web/live/god_mode_test.exs` | 7 tests for kill switch state machine |

### Modified Files
| File | Change |
|------|--------|
| `lib/observatory_web/live/dashboard_live.ex` | ~30 mount assigns + ~15 event handler delegations for Phase 5 views |
| `lib/observatory_web/live/dashboard_live.html.heex` | Nav tabs + 6 dispatch blocks with attr passing |
| `lib/observatory_web/live/dashboard_navigation_handlers.ex` | restore_view_mode handler (6-atom case match) |
| `lib/observatory_web/live/dashboard_session_control_handlers.ex` | Kill switch handlers + global instructions handlers |
| `assets/js/app.js` | ViewModePersistence hook + keyboard shortcuts 1-6 |
| `assets/css/app.css` | god-mode-panel, god-mode-button-danger, god-mode-border classes |

### EXP-003 Result: ADOPT
Model tiering per task complexity works. Opus for anchor tasks, sonnet for well-specified components, haiku for pure verification. Equal quality, estimated 60-70% cost savings on worker tokens.

### Quality Notes (non-blocking)
- Panel container CSS repeated 10x across components -- extract shared panel component later
- dashboard_live.ex at 637 lines (pre-existing, Phase 5 added ~45 lines)

---

## Previous: Phase 4 Gateway Infrastructure & HITL COMPLETE (2026-02-22)

- 7 tasks, 6 waves, ~20 min, 204 tests
- 13 new modules, 4 migrations
- HeartbeatManager, CapabilityMap, CronScheduler, WebhookRouter, HITLRelay
- HITL endpoints + OperatorAuth + audit trail
- Commit: eba293d

### Previous Milestones
- Phase 3: Topology & Entropy (7 tasks, 113 tests) -- commit 81f6054
- Phase 2: Gateway Core (5 tasks, 65 tests) -- commit ffff26d
- Phase 1: DecisionLog Schema (4 tasks, 36 tests) -- commit 2a10e77
- Mode C Pipeline: 7 FRDs -> 5 phases, 24 sections, 77 tasks, 225 subtasks
- Mode B Pipeline: 12 ADRs -> 6 FRDs -> 79 UCs

### Next Steps
- [ ] Fix phase-to-dag.sh: --start-id flag + append mode (IDs start at 1 instead of continuing)
- [ ] Extract shared panel component (repeated CSS classes)
- [ ] Visual verification: browser test of topology rendering
- [ ] MONAD_LESSON_LOG.md evaluation for upstream skill amendments
- [ ] mTLS panel: show "Not configured" (honest placeholder, no backend)

## Architecture Reminders

- Phoenix LiveView on port 4005
- Event-driven: hooks -> POST /api/events -> Ash.create + PubSub -> LiveView
- Zero warnings: `mix compile --warnings-as-errors`
- Module size limit: 200-300 lines max
- embed_templates pattern: .ex (logic) + .heex (templates)
- Six view modes: fleet_command (default), session_cluster, registry, scheduler, forensic, god_mode
- Keyboard shortcuts: 1-6 for views, Escape to clear selections
