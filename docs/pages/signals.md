# Signals Page

## Overview

The Signals page is the live nervous-system view of the app.

Current architecture:

- runtime facade: `Ichor.Signals`
- discoverable Ash domain: `Ichor.SignalBus`
- internal delivery authority for messages: `Ichor.Signals.Bus`
- canonical event buffer: `Ichor.Signals.EventStream`

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

- `Ichor.Signals.Event`
- `Ichor.Signals.Operations`
- `Ichor.Signals.TaskProjection`
- `Ichor.Signals.ToolFailure`

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

Some `dag` naming still exists in Signals, but it is intentional mesh topology,
not Factory pipeline execution.

That includes:

- `mesh:dag_delta`
- `Ichor.Mesh.CausalDag`
- `Ichor.Mesh.EventBridge`

This is separate from the `Pipeline` / `PipelineTask` execution model in
Factory.

## Key Files

- [/Users/xander/code/www/kardashev/observatory/lib/ichor/signal_bus.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signal_bus.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/catalog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/catalog.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/operations.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/operations.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/bus.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/bus.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/runtime.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/runtime.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/event_stream.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/event_stream.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/tool_failure.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/tool_failure.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/task_projection.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/task_projection.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/agent_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/agent_watchdog.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/mesh/supervisor.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/mesh/supervisor.ex)
