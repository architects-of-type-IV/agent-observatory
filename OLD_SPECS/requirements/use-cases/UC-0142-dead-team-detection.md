---
id: UC-0142
title: Detect and exclude dead event-derived teams from dashboard
status: draft
parent_fr: FR-5.18
adrs: [ADR-012]
---

# UC-0142: Detect and Exclude Dead Event-Derived Teams from Dashboard

## Intent
Event-derived teams that have been inactive for more than 300 seconds and have no corresponding disk entry are classified as dead. Dead teams have `dead?: true` set in their map and are excluded from the dashboard `:teams` assign by `prepare_assigns/1`. Disk-sourced teams are never classified as dead regardless of member activity.

## Primary Actor
`ObservatoryWeb.DashboardTeamHelpers`

## Supporting Actors
- `detect_dead_teams/2` internal function
- `prepare_assigns/1` (applies `Enum.reject(&(&1[:dead?]))`)
- `DateTime.utc_now()` for age computation

## Preconditions
- Merged teams list is available (from UC-0139).
- `DateTime.utc_now()` is accessible.
- Each team has a `source` field (`:disk` or `:events`).

## Trigger
`prepare_assigns/1` calls `detect_dead_teams(merged_teams, now)` and then `Enum.reject/2`.

## Main Success Flow
1. For each team with `source: :events`:
   a. Check that no corresponding entry exists in `disk_teams` (already guaranteed by merge logic).
   b. Check that all members have `:status` in `[:ended, :idle, :unknown, nil]`.
   c. Compute the age of the most recent member event.
   d. If age > 300 seconds, set `dead?: true` in the team map.
2. Disk-sourced teams (`source: :disk`) always have `dead?: false`.
3. `prepare_assigns/1` filters: `Enum.reject(teams, & &1[:dead?])`.
4. The inspector panel also prunes any inspected dead teams.

## Alternate Flows

### A1: Event-derived team has an active member
Condition: At least one member has `status: :active` (event within 30 seconds).
Steps:
1. The team does not meet the "all members ended/idle/unknown/nil" condition.
2. `dead?: false` is set (or the key is absent).
3. The team remains in the `:teams` assign.

## Failure Flows

### F1: Disk-sourced team incorrectly marked dead
Condition: A code change applies dead detection to disk-sourced teams.
Steps:
1. A disk team with all idle members is incorrectly removed from the `:teams` assign.
2. The dashboard shows missing teams.
3. Code review identifies the `source: :disk` check is missing.
4. Fix: dead detection applies only to `source: :events` teams.
Result: Disk teams always present regardless of member activity.

## Gherkin Scenarios

### S1: Inactive event-derived team is marked dead and excluded
```gherkin
Scenario: Event-only team inactive for 10 minutes is excluded from dashboard
  Given an event-derived team with source: :events
  And all members have status: :ended
  And the most recent member event is 10 minutes old
  When detect_dead_teams/2 runs followed by prepare_assigns/1
  Then the team has dead?: true
  And the team is absent from socket.assigns.teams
```

### S2: Disk-sourced team is never marked dead
```gherkin
Scenario: Disk team with all idle members is never marked dead
  Given a disk-sourced team with source: :disk
  And all members have status: :idle
  And the most recent event is 20 minutes old
  When detect_dead_teams/2 runs
  Then the team has dead?: false
  And the team remains in socket.assigns.teams
```

### S3: Active event-derived team is not dead
```gherkin
Scenario: Event-only team with one active member is not marked dead
  Given an event-derived team with source: :events
  And one member has status: :active (event 15 seconds ago)
  When detect_dead_teams/2 runs
  Then the team does not have dead?: true
  And the team remains in socket.assigns.teams
```

## Acceptance Criteria
- [ ] A unit test with an event-derived team whose most recent event is 400 seconds old and all members are `:ended` asserts `team[:dead?] == true` and the team is absent from the output of `Enum.reject(teams, & &1[:dead?])` (S1).
- [ ] A unit test with a disk-sourced team and all `:idle` members asserts `team[:dead?] != true` (S2).
- [ ] A unit test with an event-derived team with one `:active` member asserts `team[:dead?] != true` (S3).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Merged teams list; `DateTime.utc_now()` for age threshold; `@dead_team_threshold_sec 300`
**Outputs:** Teams list with `dead?: true` set on qualifying event-derived teams; filtered `:teams` assign excluding dead teams
**State changes:** Socket `:teams` assign excludes dead teams; inspector `:inspected_teams` pruned

## Traceability
- Parent FR: [FR-5.18](../frds/FRD-005-code-architecture-patterns.md)
- ADR: [ADR-012](../../decisions/ADR-012-dual-data-sources.md)
