# ICHOR IV - Handoff

## Current Status: ADR-026 IMPLEMENTATION IN PROGRESS (2026-03-25)

268 .ex files. Build clean. Zero tests (fresh tests needed post-refactor).

### What Was Done This Session

**Phase 1-5: Deep cleanup (~4,700 lines removed)**
- 9 single-use modules inlined (a9f4ac6)
- Mesh subsystem + GenStage remnants + Fleet domain + Signals indirection deleted (f20ac4b)
- Plugin behaviour deleted (66590ff)
- 11 stale test files deleted (eeb769c)
- 10 docs updated (a212f88)
- MemoriesBridge removed (492d03b)
- Phantom LSP warnings fixed via .gitignore (492d03b)

**Phase 6: ADR-026 Signal-as-Projector pipeline (fbbd2ff, 5a47898)**

Wave 1 -- Foundation (runs alongside existing PubSub):
- `%Event{}` struct with dot-delimited topics, key-based routing
- `%Signal{}` struct emitted when accumulation threshold met
- `Ichor.Signals.Behaviour` -- 7-callback contract (topics, signal_name, init_state, handle_event, ready?, build_signal, reset)
- `Ichor.Events.Ingress` -- GenStage Producer with demand tracking
- `Ichor.Signals.Router` -- GenStage Consumer, routes by topic match
- `Ichor.Signals.SignalProcess` -- GenServer per {module, key}, DynamicSupervisor + Registry, idle shutdown, race-safe start
- `Ichor.Signals.DefaultHandler` -- logs activations

Wave 2 -- Macro, bridge, first signals:
- `use Ichor.Signal` macro -- declarative signal creation with defaults
- EventStream bridge -- hook events push `%Event{}` into Ingress
- `Ichor.Signals.Agent.ToolBudget` -- fires `"agent.tool.budget.exhausted"` on threshold
- `Ichor.Signals.Agent.MessageProtocol` -- fires `"agent.message.protocol.violated"` on comm rule breach

Review fixes (5a47898):
- Race condition in push_event/3 (match {:error, {:already_started, pid}})
- Ingress demand tracking (dispatch from handle_cast when demand > 0)
- MessageProtocol deferred DB query (rules: :pending until handle_info loads)
- Timer conflict fixed (Process.send_after instead of send_interval)
- signal_name/0 added to Behaviour contract

### Build Status
- `mix compile --warnings-as-errors`: CLEAN
- `mix test`: 0 tests

### Architecture: ADR-026 Event Flow
```
Ash Action -> %Event{} -> Ingress (Producer) -> Router (Consumer) -> SignalProcess per {module, key} -> accumulate -> ready? -> Handler
```
Naming: big to small. `agent.tool.budget.exhausted`, not `ToolBudgetExceeded`.
Event = something happened. Signal = enough happened. Handler = now act.

### Next: Wave 3 -- Wire Ash Resources
Replace FromAsh stub with real %Event{} emission in Ash action after_action callbacks:
- pipeline.run.created/completed/failed/archived
- pipeline.task.claimed/completed/failed/reset
- project.created/stage.advanced
- settings.project.created/updated/destroyed

### Old SIG items -- OBSOLETE
SIG-7, SIG-8, old Wave 2-4 are superseded by ADR-026. The catalog will be replaced by per-module topics/0 as signals are migrated.
