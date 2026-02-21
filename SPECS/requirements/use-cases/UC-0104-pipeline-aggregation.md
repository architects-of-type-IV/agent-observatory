---
id: UC-0104
title: Aggregate task list into pipeline status counts
status: draft
parent_fr: FR-4.5
adrs: [ADR-007]
---

# UC-0104: Aggregate Task List into Pipeline Status Counts

## Intent
After parsing `tasks.jsonl`, SwarmMonitor reduces the normalised task list into a `pipeline` map containing integer counts for each status category. This map drives the pipeline summary display on the Swarm Control Center dashboard.

## Primary Actor
`Observatory.SwarmMonitor`

## Supporting Actors
- `state.tasks` (normalised task list from UC-0103)

## Preconditions
- `state.tasks` is a list of normalised task maps (possibly empty).
- The `:poll_tasks` cycle has completed parsing.

## Trigger
`handle_info(:poll_tasks, state)` calls the internal `aggregate_pipeline/1` function immediately after `read_tasks/1`.

## Main Success Flow
1. SwarmMonitor calls `aggregate_pipeline(tasks)` with the normalised task list.
2. `total` is set to `length(tasks)` (all non-deleted tasks).
3. For each status in `["pending", "in_progress", "completed", "failed", "blocked"]`, the count of tasks with that `status` value is computed.
4. The resulting map `%{total: N, pending: N, in_progress: N, completed: N, failed: N, blocked: N}` is stored in `state.pipeline`.
5. The map is included in the next PubSub broadcast.

## Alternate Flows

### A1: All tasks have the same status
Condition: Every task in the list has `status == "in_progress"`.
Steps:
1. `pending`, `completed`, `failed`, and `blocked` are all 0.
2. `in_progress` equals `total`.
3. The map is valid and contains no nil values.

## Failure Flows

### F1: Task list is empty
Condition: `state.tasks` is `[]`.
Steps:
1. All counts including `total` are 0.
2. `state.pipeline` is `%{total: 0, pending: 0, in_progress: 0, completed: 0, failed: 0, blocked: 0}`.
3. The map is never `nil`.
Result: Dashboard renders zero counts without error.

## Gherkin Scenarios

### S1: Mixed-status task list produces correct counts
```gherkin
Scenario: Pipeline counts are computed correctly from a mixed task list
  Given state.tasks contains 10 tasks: 2 pending, 3 in_progress, 2 completed, 1 failed, 2 blocked
  When aggregate_pipeline/1 runs
  Then state.pipeline.total is 10
  And state.pipeline.pending is 2
  And state.pipeline.in_progress is 3
  And state.pipeline.completed is 2
  And state.pipeline.failed is 1
  And state.pipeline.blocked is 2
```

### S2: Empty task list yields all-zero pipeline
```gherkin
Scenario: Empty task list produces a pipeline map with all zero counts
  Given state.tasks is an empty list
  When aggregate_pipeline/1 runs
  Then state.pipeline.total is 0
  And all status counts in state.pipeline are 0
  And state.pipeline is not nil
```

## Acceptance Criteria
- [ ] A unit test with 10 tasks of known statuses asserts all six pipeline fields match expected counts (S1).
- [ ] A unit test with an empty list asserts `state.pipeline == %{total: 0, pending: 0, in_progress: 0, completed: 0, failed: 0, blocked: 0}` (S2).
- [ ] `state.pipeline` is never `nil` in any code path (verified by static inspection and the above tests).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `state.tasks` -- list of normalised task maps
**Outputs:** `state.pipeline` -- map with six integer fields
**State changes:** `state.pipeline` replaced on every poll cycle

## Traceability
- Parent FR: [FR-4.5](../frds/FRD-004-swarm-monitor-protocol-tracker.md)
- ADR: [ADR-007](../../decisions/ADR-007-swarm-monitor-design.md)
