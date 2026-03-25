# ICHOR IV - Handoff

## Current Status: ADR-026 PIPELINE COMPLETE (2026-03-25)

271 .ex files. Build clean. Zero tests (fresh tests needed post-refactor).

### ADR-026 Signal-as-Projector -- DONE

Full GenStage pipeline running alongside existing PubSub:

```
Hook events  -> EventStream bridge  -> %Event{} \
Ash mutations -> FromAsh notifier   -> %Event{}  --> Ingress -> Router -> SignalProcess -> Handler
Legacy signals -> Runtime bridge    -> %Event{} /
```

**Wave 1**: Event/Signal structs, Behaviour (7 callbacks), Ingress (GenStage Producer), Router (GenStage Consumer), SignalProcess (GenServer per {module, key}), DynamicSupervisor + Registry

**Wave 2**: `use Ichor.Signal` macro, EventStream bridge, Agent.ToolBudget, Agent.MessageProtocol

**Wave 3**: FromAsh notifier -- 25 action mappings across 7 Ash resources

**Wave 3.5**: ActionHandler (HITL pause, operator notify), PipelineSupervisor (rest_for_one), benchmarks (514k-1.3M events/sec)

**Wave 4**: EntropyTracker migrated to Signals.Agent.Entropy

**Short-term**: Runtime bridge -- ALL 143 PubSub signals now flow through GenStage pipeline

**Simplify**: 13 review findings fixed (race condition, demand tracking, O(n) window, stringly-typed dispatch, dead code, crash paths)

### Three Signal Modules
- `Ichor.Signals.Agent.ToolBudget` -- fires `"agent.tool.budget.exhausted"` -> HITL pause
- `Ichor.Signals.Agent.MessageProtocol` -- fires `"agent.message.protocol.violated"` -> operator notify
- `Ichor.Signals.Agent.Entropy` -- fires `"agent.entropy.loop.detected"` -> backward-compat signals

### Deep Cleanup (earlier in session)
~4,700 lines removed: Mesh subsystem, GenStage remnants, Fleet domain, Signals indirection, Plugin behaviour, stale tests, MemoriesBridge.

### Build Status
- `mix compile --warnings-as-errors`: CLEAN
- `mix test`: 0 tests

### Research Completed (not yet implemented)

**Medium-term: Dashboard migration**
- Dashboard subscribes to 14 old PubSub categories + "signals:feed"
- New pipeline broadcasts `{:signal_activated, %Signal{}}` on `"signal:<name>"` topics
- No topic collisions -- can subscribe to both simultaneously
- Minimal change: add `dispatch({:signal_activated, %Signal{}}, socket)` in DashboardInfoHandlers

**Long-term: Durable event storage**
- Two Ash resources: `StoredEvent` (append-only event log) + `Checkpoint` (last processed event per signal per key)
- Async writes via Task.Supervisor in Ingress (per ANTI-5)
- Replay on SignalProcess init from checkpoint position
- 7-day retention with Oban pruning worker
- Filter synthetic `signal.*` bridge events from persistence
- Migration: 5 additive steps, no downtime, no cutover

### Next Steps
1. Write fresh tests against the signal pipeline API
2. Implement dashboard `{:signal_activated, %Signal{}}` consumption
3. Build StoredEvent + Checkpoint Ash resources
4. Migrate remaining projectors (TeamWatchdog, ProtocolTracker, SignalManager) as event sources are available
5. Gradually replace old `Signals.emit` with direct `Ingress.push` at each source
