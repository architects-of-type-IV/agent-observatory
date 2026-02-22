---
id: UC-0025
title: Group feed events by session_id into sorted session group list
status: draft
parent_fr: FR-2.1
adrs: [ADR-002]
---

# UC-0025: Group Feed Events by session_id into Sorted Session Group List

## Intent
`ObservatoryWeb.DashboardFeedHelpers.build_feed_groups/2` partitions a flat list of events into one session group map per distinct `session_id`, then sorts groups newest-first by `start_time`. This is the entry point for the entire feed rendering pipeline; all downstream segment, tool-pair, and timeline logic depends on a correctly structured session group list.

## Primary Actor
System

## Supporting Actors
- `ObservatoryWeb.DashboardFeedHelpers`
- `build_session_group/3` (called per distinct session)

## Preconditions
- A list of event maps is available, each with a `session_id` field.
- A teams list (possibly empty) is available for agent name resolution.

## Trigger
`DashboardFeedHelpers.build_feed_groups(events, teams)` is called from `prepare_assigns/1` when `view_mode == :feed` or when the feed view subscribes to event updates.

## Main Success Flow
1. `build_feed_groups/2` receives a list of events from multiple sessions and a teams list.
2. Events are partitioned by `session_id` using `Enum.group_by/2`.
3. For each distinct `session_id`, `build_session_group/3` is called with the session's events, `session_id`, and teams.
4. The resulting list of session group maps is sorted descending by each group's `:start_time`.
5. The sorted list is returned; the feed view renders one block per group.

## Alternate Flows

### A1: All events share one session_id
Condition: All events in the event list have the same `session_id`.
Steps:
1. `Enum.group_by/2` produces one key.
2. `build_session_group/3` is called once.
3. A one-element list is returned.
4. The feed renders one block containing all events.

### A2: Empty teams list passed as second argument
Condition: Caller passes `[]` as the teams argument.
Steps:
1. Agent name resolution falls back to cwd-derived names or UUID truncation.
2. Session groups are produced correctly with `agent_name` derived from cwd or short UUID.

## Failure Flows

### F1: Events list is empty
Condition: `events == []`.
Steps:
1. `Enum.group_by/2` returns `%{}`.
2. No `build_session_group/3` calls are made.
3. `build_feed_groups/2` returns `[]`.
4. The feed view renders an empty state.
Result: No crash; empty feed renders gracefully.

### F2: Event missing session_id field
Condition: An event map has no `session_id` key.
Steps:
1. `Enum.group_by(events, & &1.session_id)` maps the event under the key `nil`.
2. A `nil`-keyed session group is created.
3. The group may render at the top or bottom of the feed depending on sort order.
Result: Undefined behavior for malformed events. Prevention: event ingestion MUST ensure `session_id` is always set.

## Gherkin Scenarios

### S1: Multiple sessions produce sorted group list
```gherkin
Scenario: Events from five sessions produce five sorted session groups
  Given a list of events belonging to five distinct session_ids
  And the newest session has start_time T=100 and oldest has start_time T=10
  When build_feed_groups(events, []) is called
  Then a list of five session group maps is returned
  And the first group has start_time T=100
  And the last group has start_time T=10
```

### S2: Single session produces one-element group list
```gherkin
Scenario: All events sharing one session_id produce a single group
  Given all events have session_id "session-abc"
  When build_feed_groups(events, []) is called
  Then a list with exactly one session group is returned
  And that group has session_id "session-abc"
```

### S3: Empty events list returns empty group list
```gherkin
Scenario: Empty events list produces empty feed groups
  Given events is an empty list
  When build_feed_groups([], []) is called
  Then an empty list is returned
```

### S4: Teams list enriches agent names with team-provided values
```gherkin
Scenario: Team member entry overwrites cwd-derived agent name
  Given events include a SessionStart for session_id "sid-1" with cwd "/path/to/project"
  And teams contains a member with session_id "sid-1" and name "lead"
  When build_feed_groups(events, teams) is called
  Then the session group for "sid-1" has agent_name "lead"
  And not "project" (the cwd basename)
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/dashboard_feed_helpers_test.exs` includes a test with five sessions and asserts the returned list is sorted newest-first by `start_time` (S1).
- [ ] A test with all events sharing one `session_id` asserts a single-element list is returned (S2).
- [ ] A test with `events: []` asserts `build_feed_groups([], []) == []` (S3).
- [ ] A test with a teams list containing a named member asserts the session group `agent_name` equals the team-provided name (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `events` list of event maps, `teams` list (may be `[]`)
**Outputs:** List of session group maps sorted descending by `start_time`
**State changes:** None (pure computation)

## Traceability
- Parent FR: [FR-2.1](../frds/FRD-002-agent-block-feed.md)
- ADR: [ADR-002](../../decisions/ADR-002-agent-block-feed.md)
