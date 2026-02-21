---
id: UC-0032
title: Filter standalone events by excluding paired tool events and hidden types
status: draft
parent_fr: FR-2.8
adrs: [ADR-002]
---

# UC-0032: Filter Standalone Events by Excluding Paired Tool Events and Hidden Types

## Intent
`get_standalone_events/2` produces the list of events that appear as standalone entries in the segment timeline — neither part of a tool pair nor in the hidden types list. Two exclusion rules apply: (1) any event whose `tool_use_id` is in the set of paired IDs is excluded; (2) any event whose `hook_event_type` is in the hidden types list `[:SessionStart, :SessionEnd, :Stop, :SubagentStart, :SubagentStop, :PreCompact]` is excluded.

## Primary Actor
System

## Supporting Actors
- `ObservatoryWeb.DashboardFeedHelpers.get_standalone_events/2`
- `build_segment_timeline/2` (consumer of standalone events)

## Preconditions
- A list of events for one segment is available.
- The set of paired `tool_use_id` values is pre-computed by `pair_tool_events/1`.

## Trigger
`get_standalone_events/2` is called by `build_segment_timeline/2` during timeline construction.

## Main Success Flow
1. `get_standalone_events/2` receives segment events and the set of paired tool use IDs.
2. A `:UserMessage` event with no `tool_use_id` and `hook_event_type: :UserMessage` is evaluated.
3. Neither exclusion rule applies (not in hidden types, not a paired event).
4. The `:UserMessage` event is included in the standalone events list.
5. It appears as a `{:event, user_message_event}` tuple in the segment timeline.

## Alternate Flows

### A1: PostToolUse event is excluded because its tool_use_id is paired
Condition: A `:PostToolUse` event's `tool_use_id` matches a pre/post pair in the paired IDs set.
Steps:
1. The event's `tool_use_id` is found in the paired IDs set.
2. The event is excluded from standalone events.
3. It is rendered as part of the tool chain, not as a standalone row.

## Failure Flows

### F1: SessionStart event passes tool_use_id check but is caught by hidden types
Condition: A `:SessionStart` event has no `tool_use_id` (so it passes the paired IDs check).
Steps:
1. The `tool_use_id` check passes (nil not in set).
2. The hidden types check catches `hook_event_type: :SessionStart`.
3. The event is excluded from standalone events.
4. It is surfaced only through the session group header's `session_start` field.
Result: No duplicate rendering of `:SessionStart` events.

### F2: Event with tool_use_id but tool_use_id not in paired set
Condition: A `:PreToolUse` event with `tool_use_id: nil` was filtered out by `pair_tool_events/1`; the pre-event is not in the paired set. But its `hook_event_type` is not in the hidden types list.
Steps:
1. The paired IDs set does not contain `nil`.
2. The hidden types check does not catch `:PreToolUse`.
3. The event appears as a standalone event.
Result: Correct per FR-2.7 — nil-ID pre-events MAY appear as standalone events.

## Gherkin Scenarios

### S1: UserMessage event appears in standalone events
```gherkin
Scenario: UserMessage event with no tool_use_id is included as standalone
  Given a segment event list contains a :UserMessage event with tool_use_id nil
  And :UserMessage is not in the hidden types list
  When get_standalone_events/2 is called
  Then the :UserMessage event is in the returned standalone events list
```

### S2: PostToolUse with paired tool_use_id is excluded from standalone events
```gherkin
Scenario: Paired PostToolUse event is not a standalone event
  Given a :PostToolUse event with tool_use_id "tid-1"
  And "tid-1" is in the set of paired tool_use_ids
  When get_standalone_events/2 is called
  Then the :PostToolUse event is not in the standalone events list
```

### S3: SessionStart is excluded by hidden types filter
```gherkin
Scenario: SessionStart event is excluded by the hidden types list
  Given a segment event list contains a :SessionStart event with tool_use_id nil
  When get_standalone_events/2 is called
  Then the :SessionStart event is not in the standalone events list
```

### S4: PreCompact is excluded by hidden types filter
```gherkin
Scenario: PreCompact event is excluded by the hidden types list
  Given a segment event list contains a :PreCompact event
  When get_standalone_events/2 is called
  Then the :PreCompact event is not in the standalone events list
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/dashboard_feed_helpers_test.exs` includes a test with a `:UserMessage` event and asserts it appears in the standalone events list (S1).
- [ ] A test with a `:PostToolUse` event whose `tool_use_id` is in the paired set asserts it does NOT appear in standalone events (S2).
- [ ] A test with a `:SessionStart` event asserts it does NOT appear in standalone events (S3).
- [ ] A test with a `:PreCompact` event asserts it does NOT appear in standalone events (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Segment event list, set of paired `tool_use_id` strings
**Outputs:** List of events that should appear as `{:event, event}` tuples in the segment timeline
**State changes:** None (pure computation)

## Traceability
- Parent FR: [FR-2.8](../frds/FRD-002-agent-block-feed.md)
- ADR: [ADR-002](../../decisions/ADR-002-agent-block-feed.md)
