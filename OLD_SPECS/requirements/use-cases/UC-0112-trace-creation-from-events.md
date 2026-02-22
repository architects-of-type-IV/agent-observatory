---
id: UC-0112
title: Create protocol traces from qualifying hook events
status: draft
parent_fr: FR-4.13
adrs: [ADR-007]
---

# UC-0112: Create Protocol Traces from Qualifying Hook Events

## Intent
ProtocolTracker listens to the `"events:stream"` PubSub topic and creates a trace entry in the ETS table for three specific event types: `SendMessage` PreToolUse events, `TeamCreate` PreToolUse events, and `SubagentStart` events. All other event types are silently ignored. Each trace captures who sent what, to whom, and what protocol hop was used.

## Primary Actor
`Observatory.ProtocolTracker`

## Supporting Actors
- Hook event payloads arriving on `"events:stream"` PubSub
- ETS table `:protocol_traces`
- `insert_trace/1` internal function

## Preconditions
- ProtocolTracker is running with `:protocol_traces` table created.
- ProtocolTracker is subscribed to `"events:stream"`.
- A hook event has been published to `"events:stream"`.

## Trigger
`handle_info({:event, event}, state)` is invoked when an event arrives on the subscribed PubSub topic.

## Main Success Flow (SendMessage trace)
1. An event arrives with `event_type == "PreToolUse"` and `tool_name == "SendMessage"`.
2. ProtocolTracker extracts `from: event.session_id`.
3. `to` is extracted from `payload["tool_input"]["recipient"]` or `payload["tool_input"]["target_agent_id"]`.
4. `id` is set to `event.tool_use_id`; if absent, a random 8-byte hex string is generated.
5. A trace map is built: `%{id: id, type: :send_message, from: from, to: to, timestamp: now, hops: [%{protocol: :http, status: :received, detail: "PreToolUse/SendMessage"}]}`.
6. `insert_trace/1` writes the trace to `:protocol_traces`.
7. `state.trace_count` is incremented.

## Alternate Flows

### A1: TeamCreate event creates a team_create trace
Condition: `event_type == "PreToolUse"` and `tool_name == "TeamCreate"`.
Steps:
1. `to` is set to `"system"`.
2. `content` preview is set to the `team_name` from `payload["tool_input"]["team_name"]`.
3. Trace type is `:team_create`.
4. Inserted into ETS.

### A2: SubagentStart event creates an agent_spawn trace
Condition: `event_type == "SubagentStart"`.
Steps:
1. `to` is extracted from `payload["subagent_id"]`.
2. `from` is set to `event.session_id`.
3. Trace type is `:agent_spawn`.
4. Inserted into ETS.

### A3: tool_use_id is absent
Condition: The event has no `tool_use_id` field.
Steps:
1. A random 8-byte hex string is generated via `:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)`.
2. This becomes the trace `id`.

## Failure Flows

### F1: Non-qualifying event type arrives
Condition: A `PostToolUse` event for `Bash` arrives on `"events:stream"`.
Steps:
1. The event is silently dropped.
2. `state.trace_count` is not incremented.
3. No ETS write occurs.
Result: No side effects from non-qualifying events.

## Gherkin Scenarios

### S1: SendMessage PreToolUse creates a send_message trace
```gherkin
Scenario: SendMessage PreToolUse event creates a trace with http hop
  Given a PreToolUse event with tool_name "SendMessage", tool_use_id "abc123"
  And tool_input contains recipient "worker-a" and content "hello"
  When the event arrives on "events:stream"
  Then ProtocolTracker.get_traces() contains a trace with id "abc123"
  And the trace has type :send_message, to "worker-a", and one hop with protocol :http
```

### S2: TeamCreate PreToolUse creates a team_create trace
```gherkin
Scenario: TeamCreate PreToolUse event creates a trace with to "system"
  Given a PreToolUse event with tool_name "TeamCreate"
  And tool_input contains team_name "my-team"
  When the event arrives on "events:stream"
  Then ProtocolTracker.get_traces() contains a trace with type :team_create and to "system"
```

### S3: Non-qualifying event is silently ignored
```gherkin
Scenario: PostToolUse Bash event is ignored with no trace created
  Given ProtocolTracker has 0 traces
  When a PostToolUse event for Bash arrives on "events:stream"
  Then ProtocolTracker.get_traces() still returns an empty list
  And state.trace_count remains 0
```

### S4: Event without tool_use_id gets a generated id
```gherkin
Scenario: Missing tool_use_id results in a generated trace id
  Given a SubagentStart event with no tool_use_id field
  When the event arrives on "events:stream"
  Then ProtocolTracker.get_traces() contains a trace
  And the trace id is a non-empty hex string
```

## Acceptance Criteria
- [ ] A test publishing a `PreToolUse/SendMessage` event to `"events:stream"` asserts `ProtocolTracker.get_traces/0` returns a list containing a trace with `type: :send_message` and `to: "worker-a"` (S1).
- [ ] A test publishing a `PostToolUse/Bash` event asserts `ProtocolTracker.get_traces/0` returns `[]` (S3).
- [ ] A test publishing a `SubagentStart` event with no `tool_use_id` asserts the returned trace has a non-empty string `id` (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Hook event maps from `"events:stream"` PubSub; event fields `event_type`, `tool_name`, `tool_use_id`, `session_id`, `payload`
**Outputs:** Trace map written to `:protocol_traces` ETS table
**State changes:** `:protocol_traces` gains one entry; `state.trace_count` incremented

## Traceability
- Parent FR: [FR-4.13](../frds/FRD-004-swarm-monitor-protocol-tracker.md)
- ADR: [ADR-007](../../decisions/ADR-007-swarm-monitor-design.md)
