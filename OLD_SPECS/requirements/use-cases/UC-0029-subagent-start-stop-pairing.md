---
id: UC-0029
title: Pair SubagentStart and SubagentStop events by agent_id
status: draft
parent_fr: FR-2.5
adrs: [ADR-002]
---

# UC-0029: Pair SubagentStart and SubagentStop Events by agent_id

## Intent
`extract_subagent_spans/1` matches `:SubagentStart` events with `:SubagentStop` events using the `agent_id` from `event.payload["agent_id"]`. Both event types fire on the PARENT session's `session_id`. Unmatched starts produce in-progress spans. Unmatched stops are silently discarded — they never appear in segments or the rendered feed.

## Primary Actor
System

## Supporting Actors
- `ObservatoryWeb.DashboardFeedHelpers.extract_subagent_spans/1`
- `segment_by_spans/2` (consumer of the span list)

## Preconditions
- A sorted event list for one session is available.
- At least one `:SubagentStart` event with a `payload["agent_id"]` is present.

## Trigger
`extract_subagent_spans/1` is called by `build_segments/1` with the session's sorted events.

## Main Success Flow
1. `extract_subagent_spans/1` receives events including a `:SubagentStart` with `payload["agent_id"] = "ac67b7c"`.
2. A `:SubagentStop` event with `payload["agent_id"] = "ac67b7c"` is found.
3. A span map is produced: `%{agent_id: "ac67b7c", start_event: start, stop_event: stop, start_time: ..., end_time: ...}`.
4. The span is returned in the spans list.

## Alternate Flows

### A1: SubagentStart with no matching SubagentStop (in-progress)
Condition: No `:SubagentStop` event shares the same `agent_id` as a `:SubagentStart`.
Steps:
1. `Enum.find(stops, fn s -> s.agent_id == start.agent_id end)` returns `nil`.
2. The span is produced with `stop_event: nil` and `end_time: nil`.
3. The span is included in the returned spans list; the segment renders as in-progress.

## Failure Flows

### F1: SubagentStop with no matching SubagentStart is silently discarded
Condition: A `:SubagentStop` event exists for `agent_id = "xyz"` but no `:SubagentStart` with that `agent_id` is present.
Steps:
1. `extract_subagent_spans/1` only iterates over `:SubagentStart` events to produce spans.
2. The orphaned `:SubagentStop` is never referenced.
3. In `segment_by_spans/2`, when the event is encountered in the loop, the `:SubagentStop` clause discards it from the parent accumulator.
4. The stop event does not appear in any segment.
Result: No crash; the orphaned stop is silently dropped.

### F2: payload["agent_id"] is nil
Condition: A `:SubagentStart` event has `payload["agent_id"] = nil`.
Steps:
1. The span is produced with `agent_id: nil`.
2. No `:SubagentStop` with `agent_id: nil` is found (or an unintended match occurs).
3. The span may be treated as in-progress or incorrectly paired.
Result: Undefined behavior. Prevention: event ingestion MUST ensure `payload["agent_id"]` is always a non-nil string for `:SubagentStart` and `:SubagentStop` events.

## Gherkin Scenarios

### S1: Matched start and stop pair produces complete span
```gherkin
Scenario: SubagentStart and SubagentStop with same agent_id produce a complete span
  Given a session has a :SubagentStart event with payload agent_id "ac67b7c"
  And a :SubagentStop event with payload agent_id "ac67b7c"
  When extract_subagent_spans/1 is called
  Then one span is returned with agent_id "ac67b7c"
  And the span has a non-nil stop_event
  And the span has a non-nil end_time
```

### S2: Unmatched SubagentStart produces in-progress span
```gherkin
Scenario: SubagentStart with no matching stop produces in-progress span
  Given a session has a :SubagentStart event with agent_id "abc"
  And no :SubagentStop event with agent_id "abc" exists
  When extract_subagent_spans/1 is called
  Then one span is returned with agent_id "abc"
  And stop_event is nil
  And end_time is nil
```

### S3: Orphaned SubagentStop does not appear in any segment
```gherkin
Scenario: SubagentStop with no matching start is silently discarded
  Given a session has a :SubagentStop event with agent_id "xyz"
  And no :SubagentStart event with agent_id "xyz" exists
  When build_segments/1 is called
  Then no segment references agent_id "xyz"
  And no crash occurs
```

### S4: Multiple pairs produce multiple spans
```gherkin
Scenario: Two matched start/stop pairs produce two spans
  Given a session has SubagentStart/Stop pairs for agent_ids "abc" and "def"
  When extract_subagent_spans/1 is called
  Then two spans are returned
  And one span has agent_id "abc" and one has agent_id "def"
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/dashboard_feed_helpers_test.exs` includes a test with a matched start/stop pair and asserts one span is returned with a non-nil `stop_event` and `end_time` (S1).
- [ ] A test with an unmatched `:SubagentStart` asserts the span has `stop_event: nil` and `end_time: nil` (S2).
- [ ] A test with an orphaned `:SubagentStop` asserts `build_segments/1` returns no segment containing that `agent_id` and no crash occurs (S3).
- [ ] A test with two matched pairs asserts two spans are returned with correct `agent_id` values (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Sorted event list for one session
**Outputs:** List of span maps with `agent_id`, `start_event`, `stop_event`, `start_time`, `end_time`
**State changes:** None (pure computation)

## Traceability
- Parent FR: [FR-2.5](../frds/FRD-002-agent-block-feed.md)
- ADR: [ADR-002](../../decisions/ADR-002-agent-block-feed.md)
