---
id: UC-0051
title: Store Message in ETS with Required Field Shape
status: draft
parent_fr: FR-3.2
adrs: [ADR-004, ADR-005]
---

# UC-0051: Store Message in ETS with Required Field Shape

## Intent
When `Mailbox.send_message/4` is called, the resulting message map stored in the `:observatory_mailboxes` ETS table must contain exactly the eight required fields with the correct types and default values. This field contract underpins unread counting, cleanup TTL checks, and stat computation downstream.

## Primary Actor
`Observatory.Mailbox` GenServer

## Supporting Actors
- ETS table `:observatory_mailboxes`
- `:crypto` module (ID generation)

## Preconditions
- The `Observatory.Mailbox` GenServer has started and owns the `:observatory_mailboxes` ETS table with options `[:named_table, :public, :set]`.
- The ETS table exists and is accessible.

## Trigger
A caller invokes `Observatory.Mailbox.send_message(to, from, content, opts)`.

## Main Success Flow
1. The GenServer receives the `send_message` call.
2. It generates a 16-character lowercase hex `id` via `Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)`.
3. It constructs the message map with: `id`, `from`, `to`, `content`, `type` (from `opts[:type]`, defaulting to `:text`), `timestamp` (`DateTime.utc_now()`), `read: false`, `metadata` (from `opts[:metadata]`, defaulting to `%{}`).
4. It reads the existing message list for `to` from ETS (or `[]` if absent), and prepends the new message.
5. It writes the updated list back to ETS via `:ets.insert(:observatory_mailboxes, {to, [new_message | existing]})`.
6. The message is now retrievable via `:ets.lookup(:observatory_mailboxes, to)`.

## Alternate Flows

### A1: Custom type and metadata provided via opts
Condition: Caller passes `opts: [type: :context_push, metadata: %{priority: "high"}]`.
Steps:
1. The GenServer sets `type: :context_push` and `metadata: %{priority: "high"}` in the message map.
2. All other fields remain as specified in the main flow.

### A2: Recipient has no prior messages
Condition: No entry exists in ETS for the given `to` key.
Steps:
1. `:ets.lookup/2` returns `[]`.
2. The new message list is `[new_message]`.
3. ETS insert succeeds; the recipient now has one message.

## Failure Flows

### F1: Message stored without read field
Condition: A code change omits `read: false` from the message map.
Steps:
1. The message is inserted into ETS without the `read` field.
2. The 24-hour cleanup job (`FR-3.8`) evaluates `msg.read == true` — this raises a `KeyError` or returns nil depending on map access style.
3. Cleanup either crashes or silently skips all messages for the agent.
Result: ETS accumulates messages indefinitely; cleanup is non-functional.

### F2: Message stored without timestamp field
Condition: A code change omits the `timestamp` field from the message map.
Steps:
1. `Mailbox.get_stats/0` calls `DateTime.diff(DateTime.utc_now(), msg.timestamp, :hour)` and receives a `FunctionClauseError`.
2. `get_stats/0` crashes.
Result: Stat API is non-functional; SwarmMonitor cannot display mailbox health.

## Gherkin Scenarios

### S1: Message stored with all required fields and correct defaults
```gherkin
Scenario: send_message stores a correctly shaped message map in ETS
  Given the :observatory_mailboxes ETS table exists and is empty for "agent-42"
  When Observatory.Mailbox.send_message("agent-42", "dashboard", "hello", []) is called
  Then :ets.lookup(:observatory_mailboxes, "agent-42") returns a list with one message
  And the message has a 16-character lowercase hex id
  And the message has from: "dashboard"
  And the message has to: "agent-42"
  And the message has content: "hello"
  And the message has type: :text
  And the message has read: false
  And the message has metadata: %{}
  And the message has a timestamp that is a DateTime
```

### S2: Custom opts populate type and metadata
```gherkin
Scenario: send_message with custom opts stores overridden type and metadata
  Given the :observatory_mailboxes ETS table is running
  When Observatory.Mailbox.send_message("agent-42", "dashboard", "push", [type: :context_push, metadata: %{priority: "high"}]) is called
  Then the stored message has type: :context_push
  And the stored message has metadata: %{priority: "high"}
```

### S3: Messages are stored newest-first
```gherkin
Scenario: Second message is prepended to the existing list
  Given "agent-42" already has one message in ETS
  When a second send_message call is made for "agent-42"
  Then :ets.lookup(:observatory_mailboxes, "agent-42") returns a list with two messages
  And the first element of the list is the most recently inserted message
```

## Acceptance Criteria
- [ ] `mix test` passes a test that calls `Mailbox.send_message("agent-42", "dashboard", "hello", [])` and asserts all eight fields (`id`, `from`, `to`, `content`, `type`, `timestamp`, `read`, `metadata`) are present with correct types and default values in the ETS entry (S1).
- [ ] The same test suite asserts that `opts: [type: :context_push, metadata: %{p: 1}]` produces a stored message with `type: :context_push` and `metadata: %{p: 1}` (S2).
- [ ] A test asserts that after two `send_message` calls for the same recipient, the ETS list has length 2 and the most recent message is the head (S3).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `to` (string), `from` (string), `content` (string), `opts` keyword list (optional `type:` atom, `metadata:` map).
**Outputs:** Message map inserted into ETS; `{:ok, message}` returned to caller.
**State changes:** `:observatory_mailboxes` ETS entry for `to` updated with new message prepended to list.

## Traceability
- Parent FR: [FR-3.2](../frds/FRD-003-messaging-pipeline.md)
- ADR: [ADR-005](../../decisions/ADR-005-ets-over-database.md)
