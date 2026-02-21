---
id: UC-0026
title: Build session group map with required metadata fields
status: draft
parent_fr: FR-2.2
adrs: [ADR-002]
---

# UC-0026: Build Session Group Map with Required Metadata Fields

## Intent
`build_session_group/3` produces a session group map containing the full set of metadata fields required by the `SessionGroup` component. This includes timing data, model, cwd, permission mode, source app, event and tool counts, subagent count, and the `is_active` boolean derived from the presence or absence of a `:SessionEnd` event. Missing source events (e.g., no `:SessionStart`) must be handled gracefully with fallbacks.

## Primary Actor
System

## Supporting Actors
- `ObservatoryWeb.DashboardFeedHelpers.build_session_group/3`
- Event store (source of session events)

## Preconditions
- A non-empty list of events for a single `session_id` is available.
- The teams list (possibly empty) is passed for agent name resolution.

## Trigger
`build_session_group/3` is called by `build_feed_groups/2` for each distinct `session_id`.

## Main Success Flow
1. Events for a session are sorted by `inserted_at`.
2. The `:SessionStart` event is found; `model` is extracted from `payload["model"]`.
3. The `:SessionEnd` event is found; `is_active` is set to `false`.
4. `total_duration_ms` is computed as the millisecond difference between `:SessionStart.inserted_at` and `:SessionEnd.inserted_at`.
5. All required fields are populated and the map is returned.

## Alternate Flows

### A1: Session with no :SessionStart event
Condition: Events were received mid-session; no `:SessionStart` is present.
Steps:
1. `session_start` is set to `nil`.
2. `model` falls back to the first non-nil `model_name` field found across all events.
3. `start_time` is set to the earliest `inserted_at` across all events.
4. `total_duration_ms` is set to `nil`.
5. All other fields are populated normally.

### A2: Active session with no :SessionEnd event
Condition: The session is still running; no `:SessionEnd` event exists.
Steps:
1. `session_end` is set to `nil`.
2. `is_active` is set to `true`.
3. `total_duration_ms` is set to `nil`.

## Failure Flows

### F1: Event list contains events but all are infrastructure events with no usable fields
Condition: All events are `:SubagentStart` / `:SubagentStop` type with no `model_name`, `cwd`, or timestamps.
Steps:
1. `model` falls back to `nil`.
2. `cwd` is `nil`.
3. `start_time` is set to the earliest `inserted_at` available.
4. The group is returned with nil fallbacks; the `SessionGroup` component renders with placeholders.
Result: No crash; graceful degradation with nil-safe rendering.

## Gherkin Scenarios

### S1: Complete session with SessionStart and SessionEnd produces all fields
```gherkin
Scenario: Session with start and end events produces full metadata map
  Given a session has a :SessionStart event with payload model "claude-sonnet-4-6" at T=100
  And a :SessionEnd event at T=5100
  When build_session_group/3 is called
  Then the group has model "claude-sonnet-4-6"
  And is_active is false
  And total_duration_ms is 5000
  And session_start is the :SessionStart event
  And session_end is the :SessionEnd event
```

### S2: Active session with no SessionEnd sets is_active true
```gherkin
Scenario: Session with no :SessionEnd event is marked active
  Given a session has a :SessionStart event but no :SessionEnd event
  When build_session_group/3 is called
  Then is_active is true
  And total_duration_ms is nil
  And session_end is nil
```

### S3: Session missing SessionStart falls back gracefully
```gherkin
Scenario: Missing :SessionStart uses fallback values
  Given a session has no :SessionStart event
  And has events with model_name "claude-opus-4-6" on some events
  When build_session_group/3 is called
  Then session_start is nil
  And model is "claude-opus-4-6" (first non-nil model_name fallback)
  And total_duration_ms is nil
  And start_time is the earliest inserted_at across all events
```

### S4: event_count and tool_count are correct
```gherkin
Scenario: event_count and tool_count reflect actual event counts
  Given a session has 10 events total, 4 of which are :PreToolUse events
  When build_session_group/3 is called
  Then event_count is 10
  And tool_count is 4
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/dashboard_feed_helpers_test.exs` includes a test with a complete session (SessionStart + SessionEnd) and asserts all 16 required fields are present with correct values (S1).
- [ ] A test with no `:SessionEnd` event asserts `is_active == true` and `total_duration_ms == nil` (S2).
- [ ] A test with no `:SessionStart` event asserts `session_start == nil`, `total_duration_ms == nil`, and `start_time` equals the earliest `inserted_at` (S3).
- [ ] A test with 10 events (4 `:PreToolUse`) asserts `event_count == 10` and `tool_count == 4` (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** List of event maps for one `session_id`, teams list
**Outputs:** Session group map with all required fields (see FR-2.2 table)
**State changes:** None (pure computation)

## Traceability
- Parent FR: [FR-2.2](../frds/FRD-002-agent-block-feed.md)
- ADR: [ADR-002](../../decisions/ADR-002-agent-block-feed.md)
