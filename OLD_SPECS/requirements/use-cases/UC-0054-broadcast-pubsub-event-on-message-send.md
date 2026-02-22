---
id: UC-0054
title: Broadcast PubSub Event on Message Send
status: draft
parent_fr: FR-3.5
adrs: [ADR-004, ADR-005]
---

# UC-0054: Broadcast PubSub Event on Message Send

## Intent
After each successful ETS insert, `Mailbox.send_message/4` broadcasts a `{:new_mailbox_message, message}` event on the `"agent:#{to}"` PubSub topic. The message map in the broadcast payload is identical to the map stored in ETS, ensuring any subscribed LiveView or process receives a complete, well-formed message struct and can immediately refresh unread counts without a secondary ETS read.

## Primary Actor
`Observatory.Mailbox` GenServer

## Supporting Actors
- `Phoenix.PubSub` (`Observatory.PubSub`)
- `ObservatoryWeb.DashboardLive` (subscriber)

## Preconditions
- The `Observatory.PubSub` supervisor is running.
- The ETS insert step (FR-3.2) has completed successfully within the same `send_message/4` call.
- At least one process is subscribed to `"agent:#{to}"`.

## Trigger
Completion of the ETS insert step inside `Mailbox.send_message/4`.

## Main Success Flow
1. The Mailbox GenServer has constructed and inserted the message map into ETS.
2. The GenServer calls `Phoenix.PubSub.broadcast(Observatory.PubSub, "agent:#{to}", {:new_mailbox_message, message})` where `message` is the same map inserted into ETS.
3. PubSub delivers `{:new_mailbox_message, message}` to all processes subscribed to `"agent:#{to}"`.
4. `DashboardLive.handle_info({:new_mailbox_message, message}, socket)` fires and calls `handle_new_mailbox_message/2`, which invokes `refresh_mailbox_assigns/1`.
5. The dashboard re-renders with updated unread counts.

## Alternate Flows

### A1: No subscribers on the topic
Condition: No process has called `Phoenix.PubSub.subscribe/2` for `"agent:#{to}"`.
Steps:
1. The PubSub broadcast succeeds (fire-and-forget; no subscribers receive it).
2. The Mailbox GenServer continues and returns `{:ok, message}`.
3. No LiveView updates; unread count refreshes only on next page load or explicit poll.

## Failure Flows

### F1: PubSub broadcast skipped
Condition: A code change omits the `Phoenix.PubSub.broadcast/3` call after the ETS insert.
Steps:
1. ETS and CommandQueue writes complete successfully.
2. No `{:new_mailbox_message, _}` event reaches any subscriber.
3. `DashboardLive.handle_info` is never triggered for this message.
4. The dashboard does not refresh; the operator sees no real-time indication of the new message.
Result: Messages accumulate in ETS silently; the operator must manually reload to see them. This is the exact failure mode remedied by ADR-004.

### F2: Incomplete message map broadcast
Condition: The broadcast payload is a truncated or different map than the one stored in ETS.
Steps:
1. `DashboardLive.handle_info` receives a map missing required fields (e.g., no `read` field).
2. `refresh_mailbox_assigns/1` calls `Mailbox.unread_count/1`, which reads from ETS and is unaffected.
3. However, if any handler pattern-matches on broadcast payload fields, it may crash.
Result: Intermittent `FunctionClauseError` or `KeyError` in the LiveView process; dashboard restarts.

## Gherkin Scenarios

### S1: Subscribed LiveView receives PubSub event after send
```gherkin
Scenario: Dashboard receives {:new_mailbox_message, message} after Mailbox.send_message
  Given DashboardLive is mounted and subscribed to "agent:dashboard"
  When Observatory.Mailbox.send_message("dashboard", "agent-42", "reply", []) is called
  Then DashboardLive.handle_info receives {:new_mailbox_message, message}
  And the message map includes all eight required fields (id, from, to, content, type, timestamp, read, metadata)
  And refresh_mailbox_assigns/1 is called
  And the dashboard unread count updates without a page reload
```

### S2: No subscriber — broadcast succeeds silently
```gherkin
Scenario: PubSub broadcast succeeds even with no subscribers
  Given no process is subscribed to "agent:orphan-session"
  When Observatory.Mailbox.send_message("orphan-session", "dashboard", "ping", []) is called
  Then Phoenix.PubSub.broadcast/3 returns :ok
  And Mailbox.send_message/4 returns {:ok, message}
  And no crash occurs
```

### S3: Skipping broadcast prevents real-time dashboard update
```gherkin
Scenario: Omitted PubSub broadcast leaves dashboard unrefreshed
  Given DashboardLive is subscribed to "agent:dashboard"
  And the PubSub broadcast step is absent from Mailbox.send_message/4
  When a message is sent to "dashboard"
  Then DashboardLive.handle_info is never called for this message
  And the dashboard unread count does not change until the next page load
```

## Acceptance Criteria
- [ ] `mix test` passes a test using `Phoenix.PubSub.subscribe(Observatory.PubSub, "agent:test-agent")` before calling `Mailbox.send_message("test-agent", "dashboard", "hello", [])`, then asserting `assert_receive {:new_mailbox_message, %{id: _, from: "dashboard", to: "test-agent", read: false}}` (S1).
- [ ] The received message map contains all eight required fields defined in FR-3.2 (S1).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** The fully constructed message map (same as the ETS entry).
**Outputs:** `{:new_mailbox_message, message}` delivered to all subscribers of `"agent:#{to}"`.
**State changes:** No additional state change; PubSub is a broadcast side effect.

## Traceability
- Parent FR: [FR-3.5](../frds/FRD-003-messaging-pipeline.md)
- ADR: [ADR-004](../../decisions/ADR-004-messaging-architecture.md)
