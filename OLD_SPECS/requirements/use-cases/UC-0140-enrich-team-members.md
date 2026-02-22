---
id: UC-0140
title: Enrich team members with runtime event data
status: draft
parent_fr: FR-5.16
adrs: [ADR-012]
---

# UC-0140: Enrich Team Members with Runtime Event Data

## Intent
`DashboardTeamHelpers.enrich_team_members/3` merges event-derived runtime data into each disk-sourced team member map. The enriched member gains computed keys: `event_count`, `latest_event`, `status`, `health`, `health_issues`, `failure_rate`, `model`, `cwd`, `permission_mode`, `current_tool`, and `uptime`. Disk-originated fields are preserved via `Map.merge/2`.

## Primary Actor
`ObservatoryWeb.DashboardTeamHelpers`

## Supporting Actors
- `prepare_assigns/1` (calls `enrich_team_members/3`)
- Session events list (from socket assigns)
- `compute_agent_health/2` internal function

## Preconditions
- Team member maps are available (from disk or event source).
- Session events are available in the socket assigns.
- `DateTime.utc_now()` is available for uptime and status computation.

## Trigger
`prepare_assigns/1` calls `enrich_team_members(teams, events, now)` during recomputation.

## Main Success Flow
1. For each member, filter events where `event.session_id == member[:agent_id]`.
2. Compute `event_count` as the length of filtered events.
3. Compute `latest_event` as the most recent event by timestamp.
4. Compute `status` by comparing `latest_event.inserted_at` with `now`:
   - If within 30 seconds: `:active`
   - If within 120 seconds: `:idle`
   - If a session-end event exists: `:ended`
   - Otherwise: `:unknown`
5. Call `compute_agent_health/2` to produce `health` and `health_issues`.
6. Compute `failure_rate`, `model`, `cwd`, `permission_mode`, `current_tool`, `uptime` from event data.
7. Merge computed keys into the disk member map via `Map.merge/2`; disk fields take precedence for shared keys.
8. Return the enriched member map.

## Alternate Flows

### A1: Member has no runtime events yet
Condition: `member[:agent_id]` does not match any event's `session_id` (agent not yet started or no events received).
Steps:
1. Filtered events list is `[]`.
2. `event_count` is 0; `latest_event` is `nil`.
3. `status` is `:unknown`; `uptime` is `nil`; all computed keys default to nil or 0.
4. Member is still included in the result.

## Failure Flows

### F1: member[:agent_id] is nil
Condition: A disk member has `agent_id: nil` (team config omitted the field).
Steps:
1. Event filtering for `nil` matches no events.
2. All computed keys default to nil or 0.
3. `status` is `:unknown`.
4. No crash occurs; `Map.merge/2` succeeds.
Result: Member included with unknown status.

## Gherkin Scenarios

### S1: Member with active events is enriched with computed status
```gherkin
Scenario: A member with recent events is enriched with status :active
  Given a disk member with agent_id "abc123"
  And 42 events exist for session_id "abc123"
  And the most recent event was 10 seconds ago
  When enrich_team_members/3 runs
  Then the member map has event_count: 42
  And status: :active
  And uptime is a positive integer (seconds since first event)
  And all disk fields are preserved
```

### S2: Member with no events has status :unknown
```gherkin
Scenario: A disk member with no matching events has status :unknown
  Given a disk member with agent_id "xyz789"
  And no events exist for session_id "xyz789"
  When enrich_team_members/3 runs
  Then the member map has event_count: 0
  And status: :unknown
  And uptime: nil
```

### S3: Member with nil agent_id does not crash
```gherkin
Scenario: A disk member with nil agent_id is enriched without error
  Given a disk member with agent_id: nil
  When enrich_team_members/3 runs
  Then no error is raised
  And the member map has status: :unknown and event_count: 0
```

## Acceptance Criteria
- [ ] A unit test with 42 events for `session_id: "abc123"` and a disk member with `agent_id: "abc123"` asserts `enriched[:event_count] == 42` and `enriched[:status] == :active` (S1).
- [ ] A unit test with no events for a member asserts `enriched[:status] == :unknown` and `enriched[:uptime] == nil` (S2).
- [ ] A unit test with `agent_id: nil` does not raise (S3).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Team member maps (from disk or events); filtered session events list; `DateTime.utc_now()`
**Outputs:** Enriched member maps with all computed runtime keys added
**State changes:** No persistent state; `prepare_assigns/1` updates socket `:teams` assign with enriched data

## Traceability
- Parent FR: [FR-5.16](../frds/FRD-005-code-architecture-patterns.md)
- ADR: [ADR-012](../../decisions/ADR-012-dual-data-sources.md)
