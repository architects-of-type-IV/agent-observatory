---
id: UC-0062
title: Broadcast Message to Multiple Recipients via broadcast_to_many
status: draft
parent_fr: FR-3.13
adrs: [ADR-004, ADR-005]
---

# UC-0062: Broadcast Message to Multiple Recipients via broadcast_to_many

## Intent
`Observatory.Mailbox.broadcast_to_many/4` delivers the same message to a list of session IDs by calling `send_message/4` individually for each recipient. This preserves the atomicity guarantees of `send_message/4` (ETS insert + CommandQueue file + PubSub broadcast) per recipient, and returns an ordered list of `{:ok, message} | {:error, reason}` results so callers can detect partial failures.

## Primary Actor
Dashboard Operator

## Supporting Actors
- `Observatory.Mailbox` GenServer (`send_message/4`)
- `Observatory.CommandQueue` GenServer
- `Phoenix.PubSub` (`Observatory.PubSub`)

## Preconditions
- `Observatory.Mailbox` and `Observatory.CommandQueue` GenServers are running.
- The caller provides a non-empty list of session ID strings.

## Trigger
The dashboard operator submits the `send_team_broadcast` form, causing the event handler to call `Observatory.Mailbox.broadcast_to_many(session_ids, "dashboard", content, opts)`.

## Main Success Flow
1. The event handler calls `Mailbox.broadcast_to_many(["a", "b", "c"], "dashboard", "start", [])`.
2. `broadcast_to_many/4` iterates over the list and calls `Mailbox.send_message("a", "dashboard", "start", [])`, then `send_message("b", ...)`, then `send_message("c", ...)`.
3. Each `send_message/4` call performs its own ETS insert, CommandQueue file write, and PubSub broadcast independently.
4. `broadcast_to_many/4` collects the results in the same order as the input list: `[{:ok, msg_a}, {:ok, msg_b}, {:ok, msg_c}]`.
5. The results list is returned to the caller.

## Alternate Flows

### A1: Empty recipient list
Condition: The caller passes `[]` as the session ID list.
Steps:
1. `broadcast_to_many/4` iterates over an empty list.
2. No `send_message/4` calls are made.
3. `broadcast_to_many/4` returns `[]`.

## Failure Flows

### F1: Delivery fails for one recipient
Condition: `send_message/4` returns `{:error, reason}` for `"b"` due to a transient filesystem error.
Steps:
1. `send_message("a", ...)` returns `{:ok, msg_a}`.
2. `send_message("b", ...)` returns `{:error, :fs_error}`.
3. `send_message("c", ...)` returns `{:ok, msg_c}`.
4. `broadcast_to_many/4` returns `[{:ok, msg_a}, {:error, :fs_error}, {:ok, msg_c}]`.
Result: Partial delivery — "a" and "c" receive the message; "b" does not. The caller can inspect the results list to identify the failed recipient.

### F2: Implemented as a single PubSub broadcast instead of per-recipient send_message
Condition: A developer implements `broadcast_to_many/4` by broadcasting a single PubSub message to a shared topic rather than calling `send_message/4` per recipient.
Steps:
1. A single PubSub event is fired, but no CommandQueue files are written per recipient.
2. Agents polling via MCP `check_inbox` find no files.
3. Only processes subscribed to the shared topic receive the broadcast.
Result: Agents do not receive the message through the MCP filesystem channel; the broadcast is silently dropped for all MCP-polling agents.

## Gherkin Scenarios

### S1: Three recipients each receive independent deliveries
```gherkin
Scenario: broadcast_to_many sends individual messages to each recipient
  Given recipients ["a", "b", "c"] are known to DashboardLive
  When Observatory.Mailbox.broadcast_to_many(["a", "b", "c"], "dashboard", "start", []) is called
  Then send_message/4 is called exactly 3 times, once per recipient
  And :ets.lookup(:observatory_mailboxes, "a") contains one message
  And :ets.lookup(:observatory_mailboxes, "b") contains one message
  And :ets.lookup(:observatory_mailboxes, "c") contains one message
  And files exist at ~/.claude/inbox/a/{id}.json, ~/.claude/inbox/b/{id}.json, ~/.claude/inbox/c/{id}.json
  And the return value is [{:ok, _}, {:ok, _}, {:ok, _}]
```

### S2: Results are returned in input order
```gherkin
Scenario: broadcast_to_many results list matches input order
  Given recipients ["first", "second", "third"]
  When Observatory.Mailbox.broadcast_to_many(["first", "second", "third"], "dashboard", "go", []) is called
  Then the first element of the result corresponds to "first"
  And the second element corresponds to "second"
  And the third element corresponds to "third"
```

### S3: Partial failure does not prevent delivery to other recipients
```gherkin
Scenario: Single recipient failure returns error for that recipient only
  Given "b" causes send_message/4 to return {:error, :reason}
  When Observatory.Mailbox.broadcast_to_many(["a", "b", "c"], "dashboard", "go", []) is called
  Then the result is [{:ok, _}, {:error, :reason}, {:ok, _}]
  And "a" and "c" have ETS entries and CommandQueue files
  And "b" does not have an ETS entry
```

### S4: Empty recipient list returns empty result
```gherkin
Scenario: broadcast_to_many with empty list returns []
  When Observatory.Mailbox.broadcast_to_many([], "dashboard", "msg", []) is called
  Then the return value is []
  And no ETS entries are created
  And no CommandQueue files are written
```

## Acceptance Criteria
- [ ] `mix test` passes a test that calls `Mailbox.broadcast_to_many(["a", "b", "c"], "dashboard", "start", [])` and asserts three ETS entries exist, three CommandQueue files exist, and the return value is `[{:ok, _}, {:ok, _}, {:ok, _}]` (S1).
- [ ] The same test asserts the result list contains three elements in the same order as the input (S2).
- [ ] A test with an empty list asserts `broadcast_to_many([], ...)` returns `[]` and no ETS entries are created (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `session_ids` (list of strings), `from` (string), `content` (string), `opts` keyword list.
**Outputs:** `[{:ok, message} | {:error, reason}]` — one element per input session ID, in input order.
**State changes:** Per recipient: ETS entry inserted, CommandQueue JSON file created, PubSub broadcast emitted.

## Traceability
- Parent FR: [FR-3.13](../frds/FRD-003-messaging-pipeline.md)
- ADR: [ADR-004](../../decisions/ADR-004-messaging-architecture.md)
