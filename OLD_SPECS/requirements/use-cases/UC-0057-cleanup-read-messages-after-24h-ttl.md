---
id: UC-0057
title: Cleanup Read Messages from ETS After 24-Hour TTL
status: draft
parent_fr: FR-3.8
adrs: [ADR-005]
---

# UC-0057: Cleanup Read Messages from ETS After 24-Hour TTL

## Intent
The `Observatory.Mailbox` GenServer runs a periodic cleanup job every 60 seconds that removes messages from ETS only when both conditions are met: the message has been marked as read (`read == true`) and the message is older than 24 hours (`timestamp` more than 24 hours in the past). Unread messages are never removed, regardless of age. This prevents unbounded ETS memory growth during long-running Observatory instances.

## Primary Actor
`Observatory.Mailbox` GenServer

## Supporting Actors
- ETS table `:observatory_mailboxes`
- `Process.send_after/3` (self-rescheduling timer)

## Preconditions
- The `Observatory.Mailbox` GenServer is running.
- The cleanup timer has been scheduled via `Process.send_after(self(), :cleanup_old_messages, 60_000)` during `init/1`.

## Trigger
The GenServer receives the `:cleanup_old_messages` message, fired 60 seconds after the previous cleanup completed.

## Main Success Flow
1. The GenServer receives `handle_info(:cleanup_old_messages, state)`.
2. It reads all entries from `:observatory_mailboxes` via `:ets.tab2list(:observatory_mailboxes)`.
3. For each `{agent_id, messages}` entry, it filters out messages where `msg.read == true AND DateTime.diff(DateTime.utc_now(), msg.timestamp, :hour) > 24`.
4. It writes back the filtered list via `:ets.insert(:observatory_mailboxes, {agent_id, kept_messages})`.
5. It reschedules the next cleanup: `Process.send_after(self(), :cleanup_old_messages, 60_000)`.
6. The GenServer returns `{:noreply, state}`.

## Alternate Flows

### A1: Agent mailbox has no read messages older than 24 hours
Condition: All messages are either unread or read within the last 24 hours.
Steps:
1. The filter retains all messages for this agent.
2. ETS is rewritten with the same list (no effective change).
3. Cleanup completes without memory reduction for this agent.

### A2: Agent mailbox has only unread messages, some older than 24 hours
Condition: Some messages are old but none have `read: true`.
Steps:
1. The filter retains all messages (unread messages are never removed regardless of age).
2. ETS is rewritten with the original list.

## Failure Flows

### F1: Cleanup timer not rescheduled
Condition: `Process.send_after(self(), :cleanup_old_messages, 60_000)` is not called at the end of `handle_info(:cleanup_old_messages, state)`.
Steps:
1. The cleanup fires once after startup.
2. No subsequent `:cleanup_old_messages` messages are sent.
3. ETS accumulates messages indefinitely after the first cleanup cycle.
Result: Memory grows without bound during long Observatory sessions. Only a GenServer restart restores cleanup behavior.

### F2: Cleanup removes unread messages
Condition: The filter condition erroneously includes messages where `read == false`.
Steps:
1. Old unread messages are deleted from ETS.
2. An agent attempting to poll via MCP `check_inbox` finds its ETS messages gone.
3. If the CommandQueue file was already acknowledged, the message is permanently lost.
Result: Messages are silently dropped before the agent can process them.

## Gherkin Scenarios

### S1: Read messages older than 24 hours are pruned
```gherkin
Scenario: Cleanup job removes eligible read messages from ETS
  Given "agent-42" has a message in ETS with read: true and timestamp 25 hours ago
  When the :cleanup_old_messages handler fires
  Then :ets.lookup(:observatory_mailboxes, "agent-42") returns an empty or shorter list
  And the old read message is no longer present
```

### S2: Unread messages are never removed regardless of age
```gherkin
Scenario: Cleanup job retains unread messages older than 24 hours
  Given "agent-42" has a message in ETS with read: false and timestamp 48 hours ago
  When the :cleanup_old_messages handler fires
  Then :ets.lookup(:observatory_mailboxes, "agent-42") still contains the unread message
```

### S3: Recent read messages are retained
```gherkin
Scenario: Cleanup job retains read messages less than 24 hours old
  Given "agent-42" has a message in ETS with read: true and timestamp 1 hour ago
  When the :cleanup_old_messages handler fires
  Then :ets.lookup(:observatory_mailboxes, "agent-42") still contains the message
```

### S4: Cleanup reschedules itself
```gherkin
Scenario: Cleanup handler reschedules the next cleanup before returning
  Given the :cleanup_old_messages handler runs
  When handle_info(:cleanup_old_messages, state) completes
  Then a new :cleanup_old_messages message is scheduled via Process.send_after with 60_000 ms delay
```

## Acceptance Criteria
- [ ] `mix test` passes a test that inserts a message into ETS with `read: true` and a timestamp 25 hours in the past, sends `:cleanup_old_messages` to the Mailbox GenServer, and asserts the message is no longer in `:ets.lookup(:observatory_mailboxes, "agent-42")` (S1).
- [ ] A test asserts that a message with `read: false` and a timestamp 48 hours in the past is NOT removed by the cleanup handler (S2).
- [ ] A test asserts that a message with `read: true` and a timestamp 1 hour in the past is NOT removed by the cleanup handler (S3).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Current ETS contents read via `:ets.tab2list/1`; current UTC time.
**Outputs:** Updated ETS entries with eligible messages removed.
**State changes:** `:observatory_mailboxes` ETS table entries modified; next cleanup timer scheduled.

## Traceability
- Parent FR: [FR-3.8](../frds/FRD-003-messaging-pipeline.md)
- ADR: [ADR-005](../../decisions/ADR-005-ets-over-database.md)
