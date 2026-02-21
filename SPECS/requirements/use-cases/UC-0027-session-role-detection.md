---
id: UC-0027
title: Detect session role as :lead or :standalone from SubagentStart events
status: draft
parent_fr: FR-2.3
adrs: [ADR-002]
---

# UC-0027: Detect Session Role as :lead or :standalone from SubagentStart Events

## Intent
`build_session_group/3` assigns a `:role` field to each session group based solely on whether the session's events contain at least one `:SubagentStart` event. Sessions that spawned subagents receive `:lead`; all others receive `:standalone`. The `:worker` and `:relay` role atoms are not produced by this function — they come from team membership data merged by the caller.

## Primary Actor
System

## Supporting Actors
- `ObservatoryWeb.DashboardFeedHelpers.build_session_group/3`
- `ObservatoryWeb.Components.Feed.SessionGroup` (renders role badge)

## Preconditions
- The session's sorted events list is available.
- Team membership data may or may not include a role override for this session.

## Trigger
The `:role` field is computed inside `build_session_group/3` during session group construction.

## Main Success Flow
1. `build_session_group/3` checks the sorted events for any event with `hook_event_type == :SubagentStart`.
2. At least one `:SubagentStart` event is found.
3. `:role` is set to `:lead`.
4. The `SessionGroup` component renders a `LEAD` badge.

## Alternate Flows

### A1: Session has no SubagentStart events — role is :standalone
Condition: No event in the session has `hook_event_type == :SubagentStart`.
Steps:
1. The check finds no `:SubagentStart` events.
2. `:role` is set to `:standalone`.
3. The `SessionGroup` component renders a `SESSION` badge.

### A2: Caller merges :worker role from team data post-construction
Condition: The team's member list includes `role: :worker` for this session.
Steps:
1. `build_session_group/3` sets `:role` to `:standalone` (no `:SubagentStart` found).
2. The caller merges team member data, overwriting `:role` with `:worker`.
3. The `SessionGroup` component renders a `WORKER` badge.
4. `build_session_group/3` itself never produces `:worker`.

## Failure Flows

### F1: build_session_group/3 produces :worker or :relay atoms
Condition: A developer adds `:worker` or `:relay` branch logic inside `build_session_group/3`.
Steps:
1. FR-2.3 is violated: these atoms MUST NOT originate from `build_session_group/3`.
2. Team data merging logic becomes confused by pre-set role values.
Result: Detection: unit tests assert the function only returns `:lead` or `:standalone`.

## Gherkin Scenarios

### S1: Session with SubagentStart events receives :lead role
```gherkin
Scenario: Presence of SubagentStart assigns :lead role
  Given a session's events include at least one event with hook_event_type :SubagentStart
  When build_session_group/3 is called
  Then the session group has role :lead
```

### S2: Session without SubagentStart events receives :standalone role
```gherkin
Scenario: Absence of SubagentStart assigns :standalone role
  Given a session's events contain no event with hook_event_type :SubagentStart
  When build_session_group/3 is called
  Then the session group has role :standalone
```

### S3: build_session_group/3 never produces :worker or :relay role atoms
```gherkin
Scenario: build_session_group/3 output is limited to :lead or :standalone
  Given any set of session events
  When build_session_group/3 is called
  Then the role field is either :lead or :standalone
  And never :worker or :relay
```

### S4: Caller can overwrite role with :worker from team data
```gherkin
Scenario: Team membership data overwrites :standalone with :worker
  Given build_session_group/3 returns a group with role :standalone
  And the team member entry for this session has role :worker
  When the caller merges team member data into the group map
  Then the group has role :worker
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/dashboard_feed_helpers_test.exs` includes a test with a session containing a `:SubagentStart` event and asserts `group.role == :lead` (S1).
- [ ] A test with no `:SubagentStart` events asserts `group.role == :standalone` (S2).
- [ ] A property-based or parameterized test asserts that `build_session_group/3` never returns `role: :worker` or `role: :relay` regardless of input (S3).
- [ ] A test that manually merges `%{role: :worker}` into the group map and asserts the merged map has `role: :worker` (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Sorted events list for one session
**Outputs:** `:role` field: `:lead` or `:standalone`
**State changes:** None (pure computation)

## Traceability
- Parent FR: [FR-2.3](../frds/FRD-002-agent-block-feed.md)
- ADR: [ADR-002](../../decisions/ADR-002-agent-block-feed.md)
