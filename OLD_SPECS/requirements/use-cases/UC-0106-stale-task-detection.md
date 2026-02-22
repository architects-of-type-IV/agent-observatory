---
id: UC-0106
title: Detect stale in-progress tasks by updated timestamp
status: draft
parent_fr: FR-4.7
adrs: [ADR-007]
---

# UC-0106: Detect Stale In-Progress Tasks by Updated Timestamp

## Intent
On every poll cycle, SwarmMonitor identifies tasks that are stuck: they have `status == "in_progress"` but their `updated` timestamp is more than 10 minutes in the past. Tasks with missing or unparseable timestamps are conservatively assumed stale. The resulting list drives dashboard warnings and the `reset_all_stale` operational action.

## Primary Actor
`Observatory.SwarmMonitor`

## Supporting Actors
- `state.tasks` (normalised task list from UC-0103)
- `DateTime.utc_now/0` for current time reference
- `DateTime.diff/3` for age computation

## Preconditions
- `state.tasks` is available after the current poll cycle's parsing step.
- The system clock is reliable.

## Trigger
`handle_info(:poll_tasks, state)` calls `detect_stale_tasks(tasks)` during the poll cycle.

## Main Success Flow
1. SwarmMonitor filters tasks to those with `status == "in_progress"`.
2. For each in-progress task, `updated` is parsed with `DateTime.from_iso8601/1`.
3. The age is computed as `DateTime.diff(DateTime.utc_now(), updated_dt, :second)`.
4. Tasks with age greater than 600 seconds (10 minutes) are collected into `stale_tasks`.
5. `state.stale_tasks` is replaced with the result list.

## Alternate Flows

### A1: Task has no updated field and falls back to created
Condition: The task was parsed with `updated` falling back to `created` (per UC-0103).
Steps:
1. The fallback timestamp is used for age computation.
2. If `created` is also absent or unparseable, the task is treated as stale.

## Failure Flows

### F1: Task's updated field is empty or unparseable
Condition: `DateTime.from_iso8601/1` returns `{:error, _}` for the `updated` value.
Steps:
1. The task is conservatively treated as stale and added to `stale_tasks`.
Result: No crash; the stale list may include tasks that are genuinely active but have bad timestamps.

### F2: Task status is not in_progress
Condition: A completed or pending task has an old timestamp.
Steps:
1. The task is filtered out before timestamp comparison.
2. The task never appears in `stale_tasks` regardless of age.
Result: Stale detection applies only to in-progress tasks.

## Gherkin Scenarios

### S1: Task updated 15 minutes ago is detected as stale
```gherkin
Scenario: In-progress task with updated timestamp 15 minutes ago is marked stale
  Given a task with status "in_progress" and updated "2026-02-21T11:00:00Z"
  And DateTime.utc_now() returns 2026-02-21T11:15:00Z
  When detect_stale_tasks/1 runs
  Then the task appears in state.stale_tasks
```

### S2: Task updated 5 minutes ago is not stale
```gherkin
Scenario: In-progress task updated 5 minutes ago is not stale
  Given a task with status "in_progress" and updated "2026-02-21T11:10:00Z"
  And DateTime.utc_now() returns 2026-02-21T11:15:00Z
  When detect_stale_tasks/1 runs
  Then the task does not appear in state.stale_tasks
```

### S3: Task with empty updated field is treated as stale
```gherkin
Scenario: In-progress task with empty updated field is conservatively marked stale
  Given a task with status "in_progress" and updated ""
  When detect_stale_tasks/1 runs
  Then the task appears in state.stale_tasks
```

### S4: Completed task with old timestamp is never stale
```gherkin
Scenario: Completed task with an old timestamp is excluded from stale detection
  Given a task with status "completed" and updated "2025-01-01T00:00:00Z"
  When detect_stale_tasks/1 runs
  Then the task does not appear in state.stale_tasks
```

## Acceptance Criteria
- [ ] A unit test with one in-progress task whose `updated` is 15 minutes in the past asserts `length(state.stale_tasks) == 1` (S1).
- [ ] A unit test with one in-progress task whose `updated` is 5 minutes in the past asserts `state.stale_tasks == []` (S2).
- [ ] A unit test with one in-progress task whose `updated` is `""` asserts `length(state.stale_tasks) == 1` (S3).
- [ ] A unit test with a completed task with a 2025 timestamp asserts `state.stale_tasks == []` (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `state.tasks`; `DateTime.utc_now()` at the moment of detection; fixed 10-minute threshold
**Outputs:** `state.stale_tasks` -- list of task maps that are in-progress and overdue
**State changes:** `state.stale_tasks` replaced on every poll cycle

## Traceability
- Parent FR: [FR-4.7](../frds/FRD-004-swarm-monitor-protocol-tracker.md)
- ADR: [ADR-007](../../decisions/ADR-007-swarm-monitor-design.md)
