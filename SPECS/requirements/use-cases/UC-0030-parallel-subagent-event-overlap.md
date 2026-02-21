---
id: UC-0030
title: Assign overlapping events to all applicable parallel subagent blocks
status: draft
parent_fr: FR-2.6
adrs: [ADR-002]
---

# UC-0030: Assign Overlapping Events to All Applicable Parallel Subagent Blocks

## Intent
When two subagents run concurrently and their time ranges overlap, events that fall within multiple spans appear in ALL applicable subagent segment blocks. `in_any_span?/2` returns true for any event whose `inserted_at` falls within at least one active span's `[start_time, end_time)` range (excluding boundary events). These shared events are excluded from the `:parent` segment.

## Primary Actor
System

## Supporting Actors
- `ObservatoryWeb.DashboardFeedHelpers.in_any_span?/2`
- `ObservatoryWeb.DashboardFeedHelpers.collect_span_events/2`
- `ObservatoryWeb.DashboardFeedHelpers.segment_by_spans/2`

## Preconditions
- Two or more subagent spans with overlapping time ranges exist in the session.
- Events exist with `inserted_at` timestamps that fall within multiple span ranges.

## Trigger
`collect_span_events/2` is called for each span during `build_segments/1` execution.

## Main Success Flow
1. Subagent A runs from T=10 to T=30; subagent B runs from T=20 to T=40.
2. An event at T=25 is processed.
3. `in_any_span?(T=25, [span_A, span_B])` returns `true` (T=25 falls within both A and B).
4. `collect_span_events/2` for span A includes the T=25 event (T=25 >= T=10 and T=25 < T=30).
5. `collect_span_events/2` for span B includes the T=25 event (T=25 >= T=20 and T=25 < T=40).
6. The T=25 event appears in both subagent A and subagent B segment blocks.
7. `segment_by_spans/2` excludes the T=25 event from the `:parent` segment.

## Alternate Flows

### A1: Event before all spans — parent segment only
Condition: An event at T=5, before both spans start at T=10.
Steps:
1. `in_any_span?(T=5, [span_A, span_B])` returns `false`.
2. The event accumulates in the `:parent` segment.
3. It does not appear in any subagent block.

### A2: Event after all spans — parent segment only
Condition: An event at T=50, after both spans end.
Steps:
1. `in_any_span?(T=50, [span_A, span_B])` returns `false`.
2. The event accumulates in the `:parent` segment after the last subagent block.

## Failure Flows

### F1: Boundary events incorrectly included in overlap
Condition: The `:SubagentStart` event itself (at T=10) is tested against span_A's range `[T=10, T=30)`.
Steps:
1. `in_any_span?/2` MUST exclude `:SubagentStart` and `:SubagentStop` boundary events by event type.
2. If boundaries are included, the start event appears in the subagent block instead of being handled by the segment header.
Result: Boundary exclusion prevents duplicate rendering.

## Gherkin Scenarios

### S1: Event in overlap zone appears in both subagent blocks
```gherkin
Scenario: Event within two concurrent subagent spans appears in both blocks
  Given subagent A spans T=10 to T=30
  And subagent B spans T=20 to T=40
  And an event exists at T=25
  When build_segments/1 is called
  Then the T=25 event appears in subagent A's events list
  And the T=25 event appears in subagent B's events list
  And the T=25 event does not appear in any :parent segment
```

### S2: Event before all spans appears only in parent segment
```gherkin
Scenario: Pre-span event is placed in the parent segment
  Given subagent A spans T=10 to T=30 and subagent B spans T=20 to T=40
  And an event exists at T=5
  When build_segments/1 is called
  Then the T=5 event appears in the :parent segment
  And the T=5 event does not appear in any subagent segment
```

### S3: SubagentStart boundary event is not included in subagent events list
```gherkin
Scenario: SubagentStart event is excluded from subagent segment events list
  Given a subagent span with a :SubagentStart event at T=10
  When collect_span_events/2 builds the subagent segment
  Then the :SubagentStart event is not in the segment's events list
  And it is accessible only via the span's start_event field
```

### S4: Non-overlapping subagents do not share events
```gherkin
Scenario: Sequential non-overlapping subagents do not share events
  Given subagent A spans T=10 to T=20 and subagent B spans T=30 to T=40
  And an event exists at T=15
  When build_segments/1 is called
  Then the T=15 event appears only in subagent A's events list
  And not in subagent B's events list
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/dashboard_feed_helpers_test.exs` includes a test with two overlapping subagent spans and an event in the overlap zone; asserts the event appears in both subagent segments and not in any parent segment (S1).
- [ ] A test with an event at T=5 (before all spans) asserts it appears only in the parent segment (S2).
- [ ] A test asserts `:SubagentStart` boundary events are not present in the subagent segment's `events` list (S3).
- [ ] A test with two non-overlapping spans and an event in only the first span's range asserts it does not appear in the second span's events (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** All spans list, event list with `inserted_at` timestamps
**Outputs:** Per-span event lists; `:parent` segment event list (excludes spanned events)
**State changes:** None (pure computation)

## Traceability
- Parent FR: [FR-2.6](../frds/FRD-002-agent-block-feed.md)
- ADR: [ADR-002](../../decisions/ADR-002-agent-block-feed.md)
