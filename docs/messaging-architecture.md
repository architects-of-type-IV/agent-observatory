# Ichor Messaging Architecture

## Current Shape

There is now one public messaging surface and one internal delivery path.

### Public surface

- `Ichor.SignalBus`
- `Ichor.Signals.Operations`

### Internal delivery path

- `Ichor.Signals.Bus`
- `Ichor.Infrastructure.AgentProcess`
- optional tmux fallback inside the infrastructure/runtime layer

## What Changed

The old scattered message wrappers were removed or collapsed:

- `Workshop.Agent` no longer owns public send/inbox actions
- `Signals.Mailbox` was deleted
- `Signals.MailboxAdapter` was deleted
- the separate `Observability.Message` read model was deleted

That means the app no longer has multiple competing public message APIs. It has
one Ash action surface and one internal bus.

## Sending

### Agent to agent

Use `Ichor.Signals.Operations.agent_send_message`.

This delegates to `Ichor.Signals.Bus.send/1`.

### Operator to agent or team

Use `Ichor.Signals.Operations.operator_send_message`.

This also delegates to `Ichor.Signals.Bus.send/1`.

### Archon to agent or team

Archon command handlers now route through `Signals.Operations`, not through a
separate mailbox resource.

## Reading

### Agent inbox

Use `Signals.Operations.check_inbox`.

Unread messages are read from `Infrastructure.AgentProcess`.

### Operator inbox

Use `Signals.Operations.check_operator_inbox`.

### Recent messages

Use `Signals.Operations.recent_messages`.

This reads from the message log maintained by `Signals.Bus`.

## Delivery Authority

`Ichor.Signals.Bus` is the single delivery authority.

Its responsibilities are:

- resolve targets
- deliver messages to runtime recipients
- keep a recent message log for UI/debugging
- emit system-level side effects like `fleet_changed` as needed

Product code should not invent parallel delivery paths around it.

## Runtime Target

`Ichor.Infrastructure.AgentProcess` is the mailbox-backed runtime process for
live agents.

It is the concrete runtime target for inbox reads and mailbox delivery.

## Related but Not Delivery

These modules are adjacent to messaging, but they are not separate message
systems:

- `Signals.ProtocolTracker`
  Debug trace correlation for protocol hops.
- `Signals.EventStream`
  General event buffer, not mailbox delivery.
- `Mesh.CausalDag`
  Causal topology, not agent inbox routing.

## Files

- [/Users/xander/code/www/kardashev/observatory/lib/ichor/signal_bus.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signal_bus.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/operations.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/operations.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/bus.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/bus.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/infrastructure/agent_process.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/infrastructure/agent_process.ex)
