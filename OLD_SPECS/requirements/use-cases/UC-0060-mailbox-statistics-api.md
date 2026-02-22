---
id: UC-0060
title: Query Mailbox Statistics Directly from ETS
status: draft
parent_fr: FR-3.11
adrs: [ADR-005]
---

# UC-0060: Query Mailbox Statistics Directly from ETS

## Intent
`Observatory.Mailbox.get_stats/0` reads the `:observatory_mailboxes` ETS table directly (without routing through the GenServer process) and returns per-agent statistics including total message count, unread count, and age of the oldest unread message. This design allows the SwarmMonitor and dashboard to query mailbox health without serializing with message delivery operations under load.

## Primary Actor
`Observatory.Mailbox` (module-level function, not GenServer call)

## Supporting Actors
- ETS table `:observatory_mailboxes`
- `DateTime` (for age calculations)

## Preconditions
- The `:observatory_mailboxes` ETS table exists and is accessible (created and owned by the `Observatory.Mailbox` GenServer, but declared `:public` so direct ETS reads are permitted).
- At least one agent mailbox entry is present in the table.

## Trigger
A caller invokes `Observatory.Mailbox.get_stats()`.

## Main Success Flow
1. `get_stats/0` calls `:ets.tab2list(:observatory_mailboxes)` to obtain all `{agent_id, [messages]}` tuples without going through the GenServer.
2. For each `{agent_id, messages}` tuple, it computes:
   - `total`: `length(messages)`
   - `unread`: `Enum.count(messages, & !&1.read)`
   - `oldest_unread_age_sec`: `DateTime.diff(DateTime.utc_now(), oldest_unread.timestamp, :second)` where `oldest_unread` is the message with the earliest `timestamp` among messages where `read == false`; `0` if no unread messages exist.
3. It returns a list of maps, one per `agent_id`.

## Alternate Flows

### A1: Agent has no unread messages
Condition: All messages for an agent have `read: true`.
Steps:
1. `oldest_unread_age_sec` is set to `0` (no unread messages).
2. The stats map for this agent has `unread: 0` and `oldest_unread_age_sec: 0`.

### A2: ETS table is empty
Condition: No agents have any messages in `:observatory_mailboxes`.
Steps:
1. `:ets.tab2list/1` returns `[]`.
2. `get_stats/0` returns `[]`.

## Failure Flows

### F1: get_stats/0 routes through GenServer instead of ETS directly
Condition: A `GenServer.call` is used instead of `:ets.tab2list/1`.
Steps:
1. Under high message volume, `get_stats/0` calls are queued behind `send_message/4` calls in the GenServer mailbox.
2. Stat queries delay message delivery.
3. SwarmMonitor stat polling degrades the messaging pipeline throughput.
Result: Performance bottleneck; stat queries and message delivery serialize unnecessarily.

### F2: Message map missing timestamp field
Condition: A message was stored without the `timestamp` field (violating FR-3.2).
Steps:
1. `DateTime.diff(DateTime.utc_now(), msg.timestamp, :second)` raises `FunctionClauseError` because `msg.timestamp` is `nil`.
2. `get_stats/0` crashes.
Result: Stat API non-functional; SwarmMonitor cannot display mailbox health.

## Gherkin Scenarios

### S1: Stats computed correctly for agent with unread messages
```gherkin
Scenario: get_stats returns correct counts and oldest unread age
  Given "agent-42" has 5 messages in ETS: 3 unread, 2 read
  And the oldest unread message has a timestamp 142 seconds ago
  When Observatory.Mailbox.get_stats() is called
  Then the result contains %{agent_id: "agent-42", total: 5, unread: 3, oldest_unread_age_sec: age}
  And age is approximately 142 (within 1 second tolerance)
```

### S2: Stats for agent with no unread messages shows zero age
```gherkin
Scenario: get_stats returns oldest_unread_age_sec: 0 when all messages are read
  Given "agent-42" has 3 messages in ETS, all with read: true
  When Observatory.Mailbox.get_stats() is called
  Then the result contains %{agent_id: "agent-42", total: 3, unread: 0, oldest_unread_age_sec: 0}
```

### S3: get_stats reads ETS directly without GenServer serialization
```gherkin
Scenario: get_stats does not block during concurrent send_message calls
  Given the Observatory.Mailbox GenServer is processing a send_message call
  When Observatory.Mailbox.get_stats() is called concurrently
  Then get_stats/0 returns immediately without waiting for the GenServer call to complete
```

## Acceptance Criteria
- [ ] `mix test` passes a test that inserts messages into ETS directly (via `Mailbox.send_message/4` plus `Mailbox.mark_read/2`) with known read/unread counts and timestamps, then calls `Mailbox.get_stats()` and asserts `%{agent_id: _, total: 5, unread: 3, oldest_unread_age_sec: age}` where `age` is within 2 seconds of the expected value (S1).
- [ ] A test asserts that when all messages are read, `oldest_unread_age_sec` is `0` (S2).
- [ ] `get_stats/0` implementation uses `:ets.tab2list(:observatory_mailboxes)` (not `GenServer.call`) — verified by code review or `grep -n "tab2list" lib/observatory/mailbox.ex` (S3).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** None (reads ETS directly).
**Outputs:** `[%{agent_id: string, total: non_neg_integer, unread: non_neg_integer, oldest_unread_age_sec: non_neg_integer}]`.
**State changes:** None (read-only ETS access).

## Traceability
- Parent FR: [FR-3.11](../frds/FRD-003-messaging-pipeline.md)
- ADR: [ADR-005](../../decisions/ADR-005-ets-over-database.md)
