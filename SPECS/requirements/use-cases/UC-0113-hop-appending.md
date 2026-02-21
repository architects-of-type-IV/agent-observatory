---
id: UC-0113
title: Append delivery hops to existing traces via cast
status: draft
parent_fr: FR-4.14
adrs: [ADR-007]
---

# UC-0113: Append Delivery Hops to Existing Traces via Cast

## Intent
External modules that handle downstream message delivery (Mailbox, CommandQueue) call ProtocolTracker to append a hop to an existing trace. The append is fire-and-forget (cast) to avoid blocking the caller. If the trace does not exist, the append is silently ignored.

## Primary Actor
`Observatory.ProtocolTracker`

## Supporting Actors
- `Observatory.Mailbox` (calls `track_mailbox_delivery/3` after ETS write)
- `Observatory.CommandQueue` (calls `track_command_write/2` after file write)
- ETS table `:protocol_traces`

## Preconditions
- ProtocolTracker is running with `:protocol_traces` table present.
- A trace with the matching ID was previously created (UC-0112) and exists in the table.

## Trigger
`Observatory.Mailbox.send_message/4` completes delivery and calls `ProtocolTracker.track_mailbox_delivery(message_id, to, from)`.

## Main Success Flow
1. `Mailbox` calls `ProtocolTracker.track_mailbox_delivery(message_id, to, from)`.
2. `GenServer.cast(ProtocolTracker, {:append_hop, message_id, %{protocol: :mailbox, status: :delivered, at: now}})` is enqueued.
3. `handle_cast/2` looks up the trace in `:protocol_traces` by `message_id`.
4. The existing trace's `hops` list is extended with the new hop.
5. The updated trace is written back to ETS via `:ets.insert/2`.

## Alternate Flows

### A1: track_command_write appends a command_queue hop
Condition: `CommandQueue` calls `track_command_write(command_id, session_id)`.
Steps:
1. `GenServer.cast/2` is called with a `%{protocol: :command_queue, status: :pending}` hop.
2. The hop is appended to the matching trace.

## Failure Flows

### F1: No trace found for the given ID
Condition: The `message_id` does not match any key in `:protocol_traces`.
Steps:
1. `:ets.lookup(:protocol_traces, message_id)` returns `[]`.
2. The handler returns `:noreply` without writing.
3. No crash or warning occurs.
Result: Silently ignored; no partial update.

## Gherkin Scenarios

### S1: Mailbox delivery appends a mailbox hop to an existing trace
```gherkin
Scenario: track_mailbox_delivery appends a mailbox hop to the matching trace
  Given a trace with id "abc123" and one existing hop exists in :protocol_traces
  When ProtocolTracker.track_mailbox_delivery("abc123", "worker-a", "dashboard") is called
  Then the trace with id "abc123" has two hops
  And the second hop has protocol :mailbox and status :delivered
```

### S2: Append with unknown ID is a no-op
```gherkin
Scenario: track_mailbox_delivery with unknown id does not crash
  Given no trace with id "unknown-id" exists in :protocol_traces
  When ProtocolTracker.track_mailbox_delivery("unknown-id", "to", "from") is called
  Then ProtocolTracker continues running without error
  And the trace count in :protocol_traces is unchanged
```

### S3: CommandQueue write appends a command_queue hop
```gherkin
Scenario: track_command_write appends a command_queue hop
  Given a trace with id "cmd-001" exists in :protocol_traces
  When ProtocolTracker.track_command_write("cmd-001", "session-xyz") is called
  Then the trace with id "cmd-001" has an additional hop with protocol :command_queue and status :pending
```

## Acceptance Criteria
- [ ] A test creates a trace, then calls `track_mailbox_delivery/3` with the matching ID, and asserts `length(trace.hops) == 2` and `Enum.at(trace.hops, 1).protocol == :mailbox` (S1).
- [ ] A test calls `track_mailbox_delivery/3` with an ID not in the table and asserts `ProtocolTracker` remains running and the trace count is unchanged (S2).
- [ ] A test calls `track_command_write/2` and asserts the trace gains a hop with `protocol: :command_queue` (S3).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Trace ID string; `to` and `from` strings; hop map with `protocol`, `status`, and `at` fields
**Outputs:** Updated trace in ETS with appended hop
**State changes:** `:protocol_traces` ETS table entry updated in-place

## Traceability
- Parent FR: [FR-4.14](../frds/FRD-004-swarm-monitor-protocol-tracker.md)
- ADR: [ADR-007](../../decisions/ADR-007-swarm-monitor-design.md)
