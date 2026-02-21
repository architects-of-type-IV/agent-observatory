---
id: UC-0139
title: Merge team data sources with disk as authoritative
status: draft
parent_fr: FR-5.15
adrs: [ADR-012]
---

# UC-0139: Merge Team Data Sources with Disk as Authoritative

## Intent
Team state arrives from two sources: `TeamWatcher` polling `~/.claude/teams/` (disk) and event-derived inference from `"events:stream"`. When a team appears in both sources, the disk representation is used and the event-derived version is discarded. `DashboardTeamHelpers.merge_team_sources/2` implements this rule.

## Primary Actor
`ObservatoryWeb.DashboardTeamHelpers`

## Supporting Actors
- `Observatory.TeamWatcher` (produces disk_teams map)
- Event-derived team inference (produces event_teams list)
- `prepare_assigns/1` (calls `merge_team_sources/2` on each tick)

## Preconditions
- Both disk_teams (map keyed by team name) and event_teams (list) are available in the socket assigns.
- `prepare_assigns/1` is executing.

## Trigger
`prepare_assigns/1` calls `DashboardTeamHelpers.merge_team_sources(event_teams, disk_teams)`.

## Main Success Flow
1. For each team in `event_teams`, check if a team with the same name exists in `disk_teams`.
2. If a disk version exists, the event-derived version is discarded.
3. All disk teams are included in the result.
4. The result list is stored in the socket's `:teams` assign.

## Alternate Flows

### A1: Team exists only in events (not yet on disk)
Condition: An agent spawned a team via events but the team config has not yet been written to disk.
Steps:
1. No disk version exists for that team name.
2. The event-derived version is included in the result.
3. On the next poll cycle, if the config appears on disk, the disk version takes over.

### A2: Team exists only on disk (no events yet)
Condition: A team config exists on disk but no corresponding events have been seen.
Steps:
1. The disk team is included in the result.
2. No event-derived version competes.
3. The team is shown in the dashboard with whatever disk data is available.

## Failure Flows

### F1: merge_team_sources prefers event-derived over disk
Condition: A code change reverses the merge priority (event beats disk).
Steps:
1. Phantom teams appear when agents crash before emitting cleanup events.
2. Membership data from disk is silently overwritten by stale event data.
3. Code review identifies the priority reversal.
4. The merge logic is corrected to disk-wins.
Result: Disk data restored as authoritative; phantom teams eliminated.

## Gherkin Scenarios

### S1: Disk version wins when team appears in both sources
```gherkin
Scenario: When a team appears in both disk and events, the disk version is used
  Given disk_teams contains "my-team" with 3 disk-sourced members
  And event_teams contains "my-team" with 2 event-sourced members
  When merge_team_sources/2 runs
  Then the result contains "my-team" with the disk-sourced representation
  And the event-sourced version is absent from the result
```

### S2: Event-only team is included until disk catches up
```gherkin
Scenario: Team seen only in events is included pending disk write
  Given disk_teams does not contain "new-team"
  And event_teams contains "new-team" with 1 event-sourced member
  When merge_team_sources/2 runs
  Then the result contains "new-team" from event sources
```

### S3: Disk-only team is always included
```gherkin
Scenario: Team present only on disk is always included in the result
  Given disk_teams contains "stable-team" with 4 members
  And event_teams is empty
  When merge_team_sources/2 runs
  Then the result contains "stable-team" from disk sources
```

## Acceptance Criteria
- [ ] A unit test calling `merge_team_sources([event_team], %{"my-team" => disk_team})` where both have `name: "my-team"` asserts the result contains the `disk_team` representation and not the `event_team` representation (S1).
- [ ] A unit test with an event-only team asserts it appears in the result (S2).
- [ ] A unit test with a disk-only team and empty event list asserts it appears in the result (S3).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `event_teams` list; `disk_teams` map (keyed by team name string)
**Outputs:** Merged list of team maps; disk version used when both sources have the same team name
**State changes:** Socket `:teams` assign updated in `prepare_assigns/1`

## Traceability
- Parent FR: [FR-5.15](../frds/FRD-005-code-architecture-patterns.md)
- ADR: [ADR-012](../../decisions/ADR-012-dual-data-sources.md)
