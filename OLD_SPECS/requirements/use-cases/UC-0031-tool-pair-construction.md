---
id: UC-0031
title: Pair PreToolUse events with PostToolUse events by tool_use_id
status: draft
parent_fr: FR-2.7
adrs: [ADR-002]
---

# UC-0031: Pair PreToolUse Events with PostToolUse Events by tool_use_id

## Intent
`pair_tool_events/1` joins `:PreToolUse` events with their corresponding `:PostToolUse` or `:PostToolUseFailure` events using `tool_use_id` as the join key. Each resulting pair map has a normalized `:status` (`:in_progress`, `:success`, or `:failure`), `:duration_ms` from the post-event, and `:tool_name` from the pre-event. Pre-events with no matching post produce in-progress pairs. Pre-events with `nil` `tool_use_id` are filtered out entirely.

## Primary Actor
System

## Supporting Actors
- `ObservatoryWeb.DashboardFeedHelpers.pair_tool_events/1`

## Preconditions
- A list of events for one segment is available.
- `:PreToolUse` events have `tool_use_id` and `tool_name` fields.
- `:PostToolUse` and `:PostToolUseFailure` events have matching `tool_use_id` and `duration_ms`.

## Trigger
`pair_tool_events/1` is called during segment construction (inside `build_segments/1`) to populate the `:tool_pairs` field of each segment.

## Main Success Flow
1. `pair_tool_events/1` receives a list of events containing a `:PreToolUse` with `tool_use_id = "tid-1"`, `tool_name = "Read"`, and a `:PostToolUse` with `tool_use_id = "tid-1"`, `duration_ms = 42`.
2. The pre-event is matched to the post-event by `tool_use_id`.
3. A pair map is returned: `%{pre: pre_event, post: post_event, status: :success, duration_ms: 42, tool_use_id: "tid-1", tool_name: "Read"}`.

## Alternate Flows

### A1: PreToolUse with no matching PostToolUse — :in_progress pair
Condition: No post-event has the same `tool_use_id` as the pre-event.
Steps:
1. No match found for the pre-event.
2. Pair map returned: `%{pre: pre_event, post: nil, status: :in_progress, duration_ms: nil, tool_use_id: "tid-x", tool_name: "Bash"}`.

### A2: PreToolUse matched to PostToolUseFailure — :failure pair
Condition: A `:PostToolUseFailure` event shares the `tool_use_id` with a pre-event.
Steps:
1. The post event type is `:PostToolUseFailure`.
2. The pair map has `status: :failure` and `duration_ms` from the failure event.

## Failure Flows

### F1: PreToolUse event with nil tool_use_id is filtered out
Condition: A `:PreToolUse` event has `tool_use_id: nil`.
Steps:
1. `pair_tool_events/1` filters out events where `e.tool_use_id` is falsy.
2. The event does not produce a pair map.
3. The event MAY appear as a standalone event if it is not in `@feed_hidden_types`.
Result: No crash; the nil-ID event is excluded from the tool chain.

## Gherkin Scenarios

### S1: Matched PreToolUse and PostToolUse produces success pair
```gherkin
Scenario: Matched tool events produce a :success pair with duration
  Given a :PreToolUse event with tool_use_id "tid-1" and tool_name "Read"
  And a :PostToolUse event with tool_use_id "tid-1" and duration_ms 42
  When pair_tool_events/1 is called with these events
  Then one pair map is returned
  And the pair has status :success
  And duration_ms is 42
  And tool_name is "Read"
  And post is the :PostToolUse event
```

### S2: Unmatched PreToolUse produces :in_progress pair
```gherkin
Scenario: PreToolUse with no matching post produces :in_progress pair
  Given a :PreToolUse event with tool_use_id "tid-x" and tool_name "Bash"
  And no :PostToolUse or :PostToolUseFailure event with tool_use_id "tid-x"
  When pair_tool_events/1 is called
  Then one pair map is returned
  And the pair has status :in_progress
  And post is nil
  And duration_ms is nil
```

### S3: PostToolUseFailure match produces :failure pair
```gherkin
Scenario: Matched PostToolUseFailure produces a :failure pair
  Given a :PreToolUse event with tool_use_id "tid-2" and tool_name "Edit"
  And a :PostToolUseFailure event with tool_use_id "tid-2" and duration_ms 10
  When pair_tool_events/1 is called
  Then the pair has status :failure
  And duration_ms is 10
```

### S4: PreToolUse with nil tool_use_id is excluded from pairs
```gherkin
Scenario: PreToolUse with nil tool_use_id is not included in pairs
  Given a :PreToolUse event with tool_use_id nil
  When pair_tool_events/1 is called
  Then no pair map is returned for that event
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/dashboard_feed_helpers_test.exs` includes a test with a matched pre/post pair and asserts `status: :success`, `duration_ms: 42`, `tool_name: "Read"` (S1).
- [ ] A test with an unmatched `:PreToolUse` asserts `status: :in_progress`, `post: nil`, `duration_ms: nil` (S2).
- [ ] A test with a `:PostToolUseFailure` match asserts `status: :failure` (S3).
- [ ] A test with a `:PreToolUse` having `tool_use_id: nil` asserts the returned pairs list does not include any pair for that event (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** List of event maps for one segment
**Outputs:** List of pair maps with fields: `pre`, `post`, `status`, `duration_ms`, `tool_use_id`, `tool_name`
**State changes:** None (pure computation)

## Traceability
- Parent FR: [FR-2.7](../frds/FRD-002-agent-block-feed.md)
- ADR: [ADR-002](../../decisions/ADR-002-agent-block-feed.md)
