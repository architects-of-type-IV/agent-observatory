---
id: UC-0034
title: Compute tool chain summary, total duration, and aggregate status
status: draft
parent_fr: FR-2.10
adrs: [ADR-002]
---

# UC-0034: Compute Tool Chain Summary, Total Duration, and Aggregate Status

## Intent
Three helper functions support the `ToolChain` component header: `chain_tool_summary/1` produces a human-readable string grouping tools by name with frequency counts; `chain_total_duration/1` sums `duration_ms` across all pairs in a chain; `chain_status/1` derives an aggregate status from the individual pair statuses, with `:in_progress` taking highest precedence. These functions are called at render time by the `ToolChain` component.

## Primary Actor
System

## Supporting Actors
- `ObservatoryWeb.DashboardFeedHelpers.chain_tool_summary/1`
- `ObservatoryWeb.DashboardFeedHelpers.chain_total_duration/1`
- `ObservatoryWeb.DashboardFeedHelpers.chain_status/1`
- `ObservatoryWeb.Components.Feed.ToolChain`

## Preconditions
- A list of tool pair maps is available (from `pair_tool_events/1`).
- Each pair map has `tool_name`, `duration_ms`, and `status` fields.

## Trigger
The `ToolChain` component calls these helpers during render with the chain's pairs list.

## Main Success Flow
1. A chain contains pairs: `[{tool_name: "Read", status: :success, duration_ms: 10}, {tool_name: "Read", status: :success, duration_ms: 15}, {tool_name: "Read", status: :success, duration_ms: 8}, {tool_name: "Edit", status: :success, duration_ms: 5}]`.
2. `chain_tool_summary([...])` groups by tool name: `Read => 3`, `Edit => 1`. Returns `"Read x3, Edit"`.
3. `chain_total_duration([...])` returns `38` (10 + 15 + 8 + 5).
4. `chain_status([...])` finds all pairs have `status: :success`. Returns `:success`.

## Alternate Flows

### A1: All duration_ms values are nil — total duration is nil
Condition: All pairs have `duration_ms: nil` (all in-progress).
Steps:
1. `chain_total_duration/1` sums nil values; returns `nil`.

### A2: Any pair has :in_progress status — chain status is :in_progress
Condition: One pair has `status: :in_progress`, others are `:success`.
Steps:
1. `chain_status/1` detects `Enum.any?(pairs, &(&1.status == :in_progress))` is true.
2. Returns `:in_progress`.

### A3: Mix of failure and success pairs (none in progress) — :has_failures
Condition: One pair has `status: :failure`, others are `:success`. No `:in_progress`.
Steps:
1. `chain_status/1` detects no `:in_progress` pairs.
2. Detects `Enum.any?(pairs, &(&1.status == :failure))` is true.
3. Returns `:has_failures`.

## Failure Flows

### F1: Empty pairs list passed to chain helpers
Condition: An empty list `[]` is passed to any helper.
Steps:
1. `chain_tool_summary([])` returns `""` (empty string or equivalent).
2. `chain_total_duration([])` returns `nil` or `0`.
3. `chain_status([])` returns `:success` (no failures, no in-progress).
Result: No crash; the `ToolChain` component handles these edge cases in rendering.

## Gherkin Scenarios

### S1: chain_tool_summary groups by name with frequency counts
```gherkin
Scenario: Three Read pairs and one Edit pair produce correct summary string
  Given a chain with pairs: [Read, Read, Read, Edit] (all :success)
  When chain_tool_summary/1 is called
  Then it returns "Read x3, Edit"
```

### S2: Single-occurrence tools appear without count suffix
```gherkin
Scenario: Unique tool names appear without x-count suffix
  Given a chain with pairs: [Bash, Read] (two unique tools)
  When chain_tool_summary/1 is called
  Then it returns "Bash, Read" (no x1 suffix)
```

### S3: chain_status returns :in_progress when any pair is in-progress
```gherkin
Scenario: In-progress pair dominates chain status
  Given a chain has one :in_progress pair and two :success pairs
  When chain_status/1 is called
  Then it returns :in_progress
```

### S4: chain_total_duration returns nil when all durations are nil
```gherkin
Scenario: All nil duration_ms values produce nil total
  Given a chain where all pairs have duration_ms nil
  When chain_total_duration/1 is called
  Then it returns nil
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/dashboard_feed_helpers_test.exs` includes a test with [Read, Read, Read, Edit] pairs and asserts `chain_tool_summary/1` returns `"Read x3, Edit"` (S1).
- [ ] A test with [Bash, Read] pairs asserts the summary contains `"Bash"` and `"Read"` each without an `x` suffix (S2).
- [ ] A test with one `:in_progress` pair and two `:success` pairs asserts `chain_status/1 == :in_progress` (S3).
- [ ] A test with all `duration_ms: nil` pairs asserts `chain_total_duration/1 == nil` (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** List of tool pair maps with `tool_name`, `duration_ms`, `status` fields
**Outputs:** `chain_tool_summary/1` → string; `chain_total_duration/1` → integer or nil; `chain_status/1` → `:in_progress | :has_failures | :success | :mixed`
**State changes:** None (pure computation)

## Traceability
- Parent FR: [FR-2.10](../frds/FRD-002-agent-block-feed.md)
- ADR: [ADR-002](../../decisions/ADR-002-agent-block-feed.md)
