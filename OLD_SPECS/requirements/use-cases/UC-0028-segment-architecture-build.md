---
id: UC-0028
title: Split session events into parent and subagent segments
status: draft
parent_fr: FR-2.4
adrs: [ADR-002]
---

# UC-0028: Split Session Events into Parent and Subagent Segments

## Intent
`build_segments/1` takes a sorted events list and produces an ordered list of segment maps, each typed as either `:parent` or `:subagent`. Parent segments contain events that fall outside all subagent spans; subagent segments are bracketed by `SubagentStart`/`SubagentStop` pairs. When no subagents are present, a single `:parent` segment containing all events is returned. In-progress subagents (no matching stop) produce segments with `end_time: nil`.

## Primary Actor
System

## Supporting Actors
- `ObservatoryWeb.DashboardFeedHelpers.build_segments/1`
- `extract_subagent_spans/1`
- `collect_span_events/2`
- `segment_by_spans/2`

## Preconditions
- A sorted (ascending by `inserted_at`) event list for one session is available.

## Trigger
`build_segments/1` is called by `build_session_group/3` during session group construction.

## Main Success Flow
1. `build_segments/1` calls `extract_subagent_spans/1` to pair `:SubagentStart` / `:SubagentStop` events by `agent_id`.
2. Two sequential subagent spans are identified: `{agent_id: "abc", ...}` and `{agent_id: "def", ...}`.
3. `segment_by_spans/2` partitions events into: parent events before first span, subagent-abc events, parent events between spans, subagent-def events, parent events after last span.
4. Five segment maps are returned in chronological order.

## Alternate Flows

### A1: No SubagentStart events — single parent segment
Condition: No `:SubagentStart` events in the session.
Steps:
1. `extract_subagent_spans/1` returns `[]`.
2. `build_segments/1` returns a single `%{type: :parent, events: all_events, ...}` map.

### A2: In-progress subagent with no matching SubagentStop
Condition: A `:SubagentStart` event exists but no `:SubagentStop` with the same `agent_id`.
Steps:
1. `extract_subagent_spans/1` produces a span with `stop_event: nil` and `end_time: nil`.
2. `collect_span_events/2` collects all events from `start_time` to end of session (no upper-bound filter).
3. The subagent segment renders as an in-progress block.

## Failure Flows

### F1: SubagentStart and SubagentStop exist but agent_ids do not match
Condition: `start.agent_id == "abc"` but all stop events have `agent_id != "abc"`.
Steps:
1. `extract_subagent_spans/1` treats `"abc"` as an unmatched start (in-progress).
2. The stop event is not referenced from any span.
3. The stop event is discarded by `segment_by_spans/2` when encountered in the main loop.
Result: The subagent renders as in-progress; no crash.

## Gherkin Scenarios

### S1: Two sequential subagents produce five segments
```gherkin
Scenario: Two sequential subagents split session into five segments
  Given a session spawns subagent "abc" from T=10 to T=30
  And spawns subagent "def" from T=40 to T=60
  And has parent events at T=5, T=35, and T=65
  When build_segments/1 is called
  Then five segments are returned in order
  And segments 1, 3, 5 have type :parent
  And segment 2 has type :subagent with agent_id "abc"
  And segment 4 has type :subagent with agent_id "def"
```

### S2: No SubagentStart events produces single parent segment
```gherkin
Scenario: Session with no subagents returns a single :parent segment
  Given a session has no :SubagentStart events
  When build_segments/1 is called
  Then exactly one segment is returned
  And that segment has type :parent
  And it contains all session events
```

### S3: In-progress subagent (no SubagentStop) produces segment with nil end_time
```gherkin
Scenario: Unmatched SubagentStart produces in-progress subagent segment
  Given a session has a :SubagentStart event with agent_id "xyz" at T=20
  And no :SubagentStop event with agent_id "xyz" exists
  When build_segments/1 is called
  Then a segment with type :subagent and agent_id "xyz" is returned
  And that segment has stop_event nil
  And end_time nil
```

### S4: Subagent segment includes required fields
```gherkin
Scenario: Subagent segment map contains all required fields
  Given a session has a matched SubagentStart/SubagentStop pair for agent_id "abc"
  When build_segments/1 is called
  Then the subagent segment map contains keys: agent_id, agent_type, start_event, stop_event, start_time, end_time, events, tool_pairs, event_count, tool_count
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/dashboard_feed_helpers_test.exs` includes a test with two sequential subagents and asserts five segments returned in order with correct types (S1).
- [ ] A test with no `:SubagentStart` events asserts a single `:parent` segment containing all events (S2).
- [ ] A test with an unmatched `:SubagentStart` asserts the segment has `stop_event: nil` and `end_time: nil` (S3).
- [ ] A test asserts all 10 required keys are present in a subagent segment map (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Sorted event list for one session
**Outputs:** Ordered list of segment maps with `:type` (`:parent` or `:subagent`) and segment-specific fields
**State changes:** None (pure computation)

## Traceability
- Parent FR: [FR-2.4](../frds/FRD-002-agent-block-feed.md)
- ADR: [ADR-002](../../decisions/ADR-002-agent-block-feed.md)
