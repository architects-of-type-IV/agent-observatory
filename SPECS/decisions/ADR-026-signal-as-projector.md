---
status: implemented
date: 2026-03-24
implemented: 2026-03-25
---

# ADR-026: Signal as Projector

## Context

The current signal system has a central `Catalog` that registers every signal name as an atom. Modules emit signals by name (`Signals.emit(:decision_log, data)`), and subscribers listen by category. The catalog owns the schema; the modules just call emit.

This creates several problems:

1. **The catalog is a central bottleneck.** Every new signal requires editing `catalog.ex`. The catalog knows every signal in the system but owns none of them.
2. **Signal data shapes are implicit.** A signal's data is a bare map. No struct, no type, no spec. Consumers pattern-match on map keys they hope exist.
3. **Formatting is orphaned.** When the MemoriesBridge needs to convert a signal to prose, it owns 40+ `narrate/2` clauses for data shapes it doesn't control. When a signal's data shape changes, the bridge breaks silently.
4. **No backpressure.** PubSub is fire-and-forget. Slow subscribers get their mailbox flooded.
5. **Events are framework noise, not domain facts.** Signal names like `new_event`, `fleet_changed`, `registry_changed` are implementation artifacts, not domain-level observations.

## Decision

**A Signal is a Projector.** Each Signal is a GenStage consumer that accumulates events, evaluates a flush condition, and calls a handler when that condition is met.

### Compact mental model

- **Event** = something happened
- **Signal** = enough happened
- **Handler** = now act

### Core rules

1. A Signal is NOT a topic. You cannot subscribe to a Signal.
2. A Signal watches one or more topics until conditions are met, then activates.
3. When a Signal activates, it publishes to `"signal:<topic>"` via PubSub.
4. Projectors stay dumb: accumulate, decide flush, call handler.
5. Real work lives in handlers (Ash Reactor, Oban job, domain module, LLM adapter, aggregator).
6. Events are domain facts (`chat.message.created`), not framework noise (`resource.updated`).
7. One event envelope everywhere.

### Event flow

```text
Ash Action
  -> Domain Event
    -> Event Bus
      -> GenStage Ingress (Producer)
        -> Signal Router (Consumer)
          -> Signal Process per {signal_name, key}
            -> Accumulate events
            -> When ready: emit Signal
              -> Signal Handler (Reactor / Oban / module / LLM)
```

### Event envelope

One struct, everywhere. No varying shapes per signal.

```elixir
%Event{
  id: Ash.UUID.generate(),
  topic: "chat.message.created",
  key: conversation_id,
  occurred_at: DateTime.utc_now(),
  causation_id: causation_id,
  correlation_id: correlation_id,
  data: %{...},
  metadata: %{...}
}
```

### Signal envelope

Emitted when a Signal process decides "enough happened."

```elixir
%Signal{
  name: "conversation.summary.ready",
  key: conversation_id,
  events: [%Event{}, ...],
  metadata: %{event_count: 5, closed?: true},
  emitted_at: DateTime.utc_now()
}
```

### Signal behaviour

Every signal module implements this contract:

```elixir
@callback topics() :: [String.t()]
@callback init_state(key :: term()) :: map()
@callback handle_event(state :: map(), event :: Event.t()) :: map()
@callback ready?(state :: map(), trigger :: :event | :timer) :: boolean()
@callback build_signal(state :: map()) :: Signal.t() | nil
@callback reset(state :: map()) :: map()
```

### GenStage topology

```
Event Bus → GenStage Ingress (Producer) → Signal Router (Consumer)
                                            → Signal Process (GenServer per {module, key})
```

- **Ingress**: GenStage producer that bridges the event bus into demand-driven flow
- **Router**: GenStage consumer that checks each event against signal modules' `topics/0` and routes to the correct Signal process
- **Signal Process**: GenServer per `{signal_module, key}`. Accumulates events, checks `ready?/2` on each event and on a timer, calls `build_signal/1` and hands to handler on flush

### PubSub is optional for core flow

PubSub is useful for:
- LiveView dashboards
- logs
- metrics
- observer tooling

But the core signal path does NOT require PubSub:

```text
Ash -> Events -> GenStage -> SignalRouter -> SignalProcess -> SignalHandler
```

When a Signal activates it MAY publish to `"signal:<topic>"` for dashboard/observability consumption, but the handler call is the primary activation path.

### Domain facts, not framework noise

```
chat.message.created       -- good: a thing happened
memory.fact.extracted      -- good: a thing happened
agent.run.completed        -- good: a thing happened

resource.updated           -- bad: framework leaked
ash.action.called          -- bad: implementation detail
new_event                  -- bad: meaningless
fleet_changed              -- bad: vague
```

### Data owns its formatting

Each domain struct owns a `format/1` function that converts it to human-readable prose. No central narrator module. When the struct changes, the formatting changes with it.

### One event can feed multiple signal families

```elixir
@signal_modules [
  Signals.ConversationSummary,
  Signals.EntityExtraction,
  Signals.FactExtraction
]
```

The router checks each event against all signal modules. One event can route into several downstream decisions.

## Consequences

### Positive

- **Backpressure.** GenStage prevents mailbox flooding on slow consumers.
- **Signals stay small.** Accumulate + decide flush + call handler. ~20-50 lines each.
- **Handlers do the real work.** Reactor, Oban, domain modules, LLM adapters.
- **Domain-native events.** Dot-delimited facts, not framework atoms.
- **One envelope.** Every event has the same shape with causation/correlation tracing.
- **Composable.** Signal activation publishes to `"signal:<topic>"` which other Signals can watch.
- **Testable.** Test the behaviour callbacks (pure functions) without processes.
- **Data owns formatting.** No orphaned narrate clauses.

### Negative

- **Migration effort.** 145 current signals across 11 categories need new topic names and signal modules.
- **GenStage learning curve.** Team needs to understand demand-driven flow.
- **Process count.** One GenServer per `{signal_module, key}` -- dynamic, cleaned up on idle.

### Implementation Status (2026-03-25)

The core GenStage pipeline is implemented:

- `Events.Ingress` (GenStage producer) -- bridges `Signals.emit` calls into demand-driven flow
- `Signals.Router` (GenStage consumer) -- routes events to SignalProcess accumulators by topic
- `Signals.SignalProcess` (transient GenServer per {module, key}) -- accumulates events, idle timeout 5 min
- `Signals.ActionHandler` -- dispatches activations to HITL/Bus/etc.
- `Signals.PipelineSupervisor` (rest_for_one) -- wraps Ingress + Router
- `Signals.Behaviour` -- callback contract
- 3 signal modules: `Agent.ToolBudget`, `Agent.MessageProtocol`, `Agent.Entropy`
- `Events.StoredEvent` (Ash resource, PostgreSQL) -- durable append-only event log
- `Signals.Checkpoint` (Ash resource, PostgreSQL) -- projector resume positions

**Not yet done:**
- Full migration of 145 atom-based signals to dot-delimited domain facts (partial)
- `MemoriesBridge` projector replacement (deleted without replacement)
- Event name normalization to `chat.message.created` style (old atom names still in use for PubSub)

### Migration path

1. Build event envelope struct and event bus
2. Build GenStage ingress (Producer)
3. Build signal router (Consumer)
4. Build signal process (GenServer with DynamicSupervisor + Registry)
5. Build signal behaviour
6. Implement first signal modules (Memories projectors) alongside existing system
7. Migrate existing signals one category at a time
8. Rewrite event names as dot-delimited domain facts
9. Remove old catalog when empty

## Related

- [ADR-026-reference-design.md](ADR-026-reference-design.md) -- Complete working example (authoritative)
- [ADR-026-findings.md](ADR-026-findings.md) -- Full codebase research findings
- ADR-014: Decision log envelope (DecisionLog struct)
- ADR-017: Causal DAG (CausalDAG.Node struct)
- ADR-023: BEAM-native agent processes (DynamicSupervisor + Registry pattern)
- [`Ingest struct`](../../lib/ichor/memories_bridge/ingest.ex) -- Memories API contract
- Memories [`tuning-session-2026-03-23.md`](/Users/xander/code/www/memories/tuning-session-2026-03-23.md) -- data quality observations
- Memories [`session-forensics-2026-03-24.md`](/Users/xander/code/www/memories/session-forensics-2026-03-24.md) -- design evolution from Narrator to Signal as Projector
