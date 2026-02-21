---
id: UC-0033
title: Build chronologically sorted segment timeline with tool chain grouping
status: draft
parent_fr: FR-2.9
adrs: [ADR-002]
---

# UC-0033: Build Chronologically Sorted Segment Timeline with Tool Chain Grouping

## Intent
`build_segment_timeline/2` merges tool pairs and standalone events into a chronologically sorted list, then groups consecutive tool pairs into `{:tool_chain, [pairs]}` tuples. Standalone events that fall between tool pairs break the chain into two separate `{:tool_chain, ...}` tuples. A single tool pair still produces a `{:tool_chain, [pair]}` tuple (single-element list). The resulting timeline drives the feed renderer, alternating between collapsible tool chains and standalone event rows.

## Primary Actor
System

## Supporting Actors
- `ObservatoryWeb.DashboardFeedHelpers.build_segment_timeline/2`

## Preconditions
- A tool pairs list (from `pair_tool_events/1`) and a standalone events list (from `get_standalone_events/2`) are available for one segment.

## Trigger
`build_segment_timeline/2` is called during segment construction with the pairs and standalone events for a segment.

## Main Success Flow
1. `build_segment_timeline/2` receives three tool pairs (at T=1, T=3, T=5) and one standalone event (at T=4).
2. All items are merged and sorted chronologically: `[pair@T1, pair@T3, event@T4, pair@T5]`.
3. Consecutive pairs at T=1 and T=3 form one chain; the standalone event at T=4 breaks the chain.
4. The pair at T=5 forms a second chain.
5. The timeline returned: `[{:tool_chain, [pair@T1, pair@T3]}, {:event, event@T4}, {:tool_chain, [pair@T5]}]`.

## Alternate Flows

### A1: Five consecutive pairs with no interleaved standalone events
Condition: No standalone events exist for the segment.
Steps:
1. All five pairs sort consecutively.
2. One chain is formed containing all five pairs.
3. Timeline: `[{:tool_chain, [p1, p2, p3, p4, p5]}]`.

### A2: Single tool pair wraps in one-element :tool_chain tuple
Condition: Only one tool pair exists in the segment.
Steps:
1. The single pair produces `{:tool_chain, [pair]}`.
2. Timeline: `[{:tool_chain, [pair]}]`.

### A3: Segment with only standalone events and no tool pairs
Condition: No tool pairs exist in the segment; only standalone events.
Steps:
1. No `{:tool_chain, ...}` tuples are produced.
2. Timeline: `[{:event, e1}, {:event, e2}, ...]`.

## Failure Flows

### F1: Pairs and events have identical timestamps — sort is non-deterministic
Condition: A tool pair and a standalone event share exactly the same `inserted_at`.
Steps:
1. The sort order between the pair and event is implementation-defined (stable sort order by type).
2. The rendered feed may show the chain before or after the event.
Result: Acceptable ambiguity for same-millisecond events. Prevention: rely on database insertion order as a secondary sort key.

## Gherkin Scenarios

### S1: Standalone event between pairs breaks the tool chain
```gherkin
Scenario: Standalone event between two pairs creates two separate tool chains
  Given segment has tool pairs at T=1, T=3, T=5 and a standalone event at T=4
  When build_segment_timeline/2 is called
  Then the timeline has three items
  And item 1 is {:tool_chain, [pair@T1, pair@T3]}
  And item 2 is {:event, event@T4}
  And item 3 is {:tool_chain, [pair@T5]}
```

### S2: Five consecutive pairs without interruption form a single chain
```gherkin
Scenario: Five consecutive pairs with no interleaved events form one chain
  Given segment has five tool pairs and no standalone events
  When build_segment_timeline/2 is called
  Then the timeline has one item
  And that item is {:tool_chain, [p1, p2, p3, p4, p5]}
```

### S3: Single pair is wrapped in a one-element tool_chain tuple
```gherkin
Scenario: Single tool pair produces {:tool_chain, [pair]} tuple
  Given segment has exactly one tool pair and no standalone events
  When build_segment_timeline/2 is called
  Then the timeline has one item
  And that item is {:tool_chain, [pair]}
```

### S4: Segment with only standalone events produces event tuples only
```gherkin
Scenario: No tool pairs produces a timeline of event tuples only
  Given segment has no tool pairs and three standalone events
  When build_segment_timeline/2 is called
  Then the timeline has three items
  And all items are {:event, event} tuples
  And no :tool_chain tuples are present
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/dashboard_feed_helpers_test.exs` includes a test with pairs at T=1, T=3, T=5 and event at T=4; asserts the timeline matches `[{:tool_chain, [p1, p3]}, {:event, e4}, {:tool_chain, [p5]}]` (S1).
- [ ] A test with five consecutive pairs and no standalone events asserts a single `{:tool_chain, [p1, p2, p3, p4, p5]}` timeline (S2).
- [ ] A test with exactly one pair asserts the timeline is `[{:tool_chain, [pair]}]` (S3).
- [ ] A test with no pairs and three standalone events asserts the timeline is three `{:event, _}` tuples in order (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Tool pairs list, standalone events list (both for one segment)
**Outputs:** Chronologically sorted list of `{:tool_chain, [pairs]}` and `{:event, event}` tuples
**State changes:** None (pure computation)

## Traceability
- Parent FR: [FR-2.9](../frds/FRD-002-agent-block-feed.md)
- ADR: [ADR-002](../../decisions/ADR-002-agent-block-feed.md)
