# Signals Page

## Overview

The Signals page is the live nervous-system view of the app.

Current architecture:

- runtime facade: `Ichor.Signals`
- discoverable Ash domain: `Ichor.SignalBus`
- internal delivery authority for messages: `Ichor.Signals.Bus`
- canonical event buffer: `Ichor.Signals.EventStream`

### GenStage Pipeline (ADR-026)

Signals now also flows through a GenStage demand-driven pipeline in parallel with PubSub broadcast:

```
Signals.emit(topic, payload)
  ├─> Phoenix.PubSub (observational broadcast -- fire and forget)
  └─> Events.Ingress (GenStage producer)
        -> Signals.Router (consumer, routes by topic)
           -> Signals.SignalProcess (per {module, key} accumulator)
              -> Signals.ActionHandler (HITL pause, Bus notification, etc.)
```

Three signal modules accumulate events per-session and trigger actions:
- `Signals.Agent.ToolBudget` -- pauses agent via HITLRelay when tool budget exhausted
- `Signals.Agent.MessageProtocol` -- tracks protocol violations
- `Signals.Agent.Entropy` -- detects repetitive loops

Durable storage:
- `Events.StoredEvent` (Ash resource, PostgreSQL) -- append-only event log populated by Ingress
- `Signals.Checkpoint` (Ash resource, PostgreSQL) -- last processed position per projector

`Observability` is no longer a separate domain for live viewing. Live tool
failures, task projections, and recent events now belong to the signals side of
the system.

## Main Panels

The page still has two major areas:

- signal catalog
- live feed

The catalog is backed by
[/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/catalog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/catalog.ex).

The live feed is backed by
[/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/event_stream.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/event_stream.ex),
with renderer dispatch under
[/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_feed](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_feed).

## SignalBus Domain

`Ichor.SignalBus` exists so Discovery and Reactor can enumerate signal-facing
Ash actions. Current resources are:

- ~~`Ichor.Signals.Event`~~ (deleted in f20ac4b)
- `Ichor.Signals.Operations`
- `Ichor.Signals.TaskProjection`
- `Ichor.Signals.ToolFailure`
- `Ichor.Signals.Checkpoint` (ADR-026 -- projector resume positions)

`Ichor.Events` domain (separate from SignalBus):
- `Events.StoredEvent` -- durable append-only event log (PostgreSQL)

Messaging-related tools exposed from the domain currently include:

- `check_operator_inbox`
- `check_inbox`
- `acknowledge_message`
- `send_message`
- `recent_messages`
- `archon_send_message`
- `agent_events`

## Messaging

The public message surface is now concentrated in
[/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/operations.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/operations.ex).

Current message architecture is:

- public Ash actions: `Signals.Operations`
- internal routing and recent-message log: `Signals.Bus`
- mailbox storage/runtime target: `Infrastructure.AgentProcess`

This replaced the older duplicated message surfaces in Workshop and the deleted
`Signals.Mailbox` / `Signals.MailboxAdapter` wrappers.

## Live Projections

The old `Observability.Error` and `Observability.Task` projections were moved
under Signals:

- `Ichor.Signals.ToolFailure`
- `Ichor.Signals.TaskProjection`

These are live read models over the event stream, not durable database-backed
history.

## Topology

**Mesh subsystem deleted (f20ac4b)**: The `Ichor.Mesh` namespace (CausalDAG, EventBridge, DecisionLog, Mesh.Supervisor) was removed. The `mesh:dag_delta` signal topic and topology pipeline no longer exist.

## Key Files

- `lib/ichor/signal_bus.ex` -- Ash domain facade
- `lib/ichor/signals/catalog.ex` -- signal definitions
- `lib/ichor/signals/operations.ex` -- public Ash actions
- `lib/ichor/signals/bus.ex` -- message delivery authority
- `lib/ichor/signals/runtime.ex` -- PubSub broadcast + Ingress bridge
- `lib/ichor/signals/event_stream.ex` -- ETS event store + broadcaster
- `lib/ichor/signals/router.ex` -- GenStage consumer (ADR-026)
- `lib/ichor/signals/signal_process.ex` -- per {module,key} accumulator GenServer (ADR-026)
- `lib/ichor/signals/action_handler.ex` -- signal action dispatch (ADR-026)
- `lib/ichor/signals/pipeline_supervisor.ex` -- rest_for_one Ingress+Router (ADR-026)
- `lib/ichor/signals/agent/tool_budget.ex` -- ToolBudget signal module (ADR-026)
- `lib/ichor/signals/agent/entropy.ex` -- Entropy signal module (ADR-026)
- `lib/ichor/signals/agent/message_protocol.ex` -- MessageProtocol signal module (ADR-026)
- `lib/ichor/signals/checkpoint.ex` -- Ash resource for projector resume (ADR-026)
- `lib/ichor/events/ingress.ex` -- GenStage producer (ADR-026)
- `lib/ichor/events/stored_event.ex` -- durable event log Ash resource (ADR-026)
- `lib/ichor/signals/tool_failure.ex`
- `lib/ichor/signals/task_projection.ex`
- ~~`lib/ichor/signals/agent_watchdog.ex`~~ (deleted, moved to `lib/ichor/projector/agent_watchdog.ex`)
- ~~`lib/ichor/mesh/supervisor.ex`~~ (deleted in f20ac4b)
