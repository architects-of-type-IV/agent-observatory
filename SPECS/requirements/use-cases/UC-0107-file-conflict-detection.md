---
id: UC-0107
title: Detect file conflicts between concurrent in-progress tasks
status: draft
parent_fr: FR-4.8
adrs: [ADR-007]
---

# UC-0107: Detect File Conflicts Between Concurrent In-Progress Tasks

## Intent
SwarmMonitor identifies pairs of in-progress tasks that claim overlapping files in their `files` lists. Detected conflicts are surfaced in the dashboard as medium-severity issues so that the swarm lead can intervene before agents corrupt each other's work.

## Primary Actor
`Observatory.SwarmMonitor`

## Supporting Actors
- `state.tasks` (normalised task list from UC-0103)
- Internal `detect_file_conflicts/1` function

## Preconditions
- `state.tasks` is available after the current poll cycle's parsing step.

## Trigger
`handle_info(:poll_tasks, state)` calls `detect_file_conflicts(tasks)` during the poll cycle.

## Main Success Flow
1. SwarmMonitor filters tasks to those with `status == "in_progress"`.
2. All unique pairs of in-progress tasks are enumerated where `task_a.id < task_b.id` (lexicographic order prevents duplicate reporting).
3. For each pair, the intersection of `task_a.files` and `task_b.files` is computed.
4. Pairs with a non-empty intersection are collected as `{task_a.id, task_b.id, shared_files}` tuples.
5. `state.file_conflicts` is replaced with the result list.

## Alternate Flows

### A1: One or both tasks have empty files lists
Condition: An in-progress task has `files: []`.
Steps:
1. The intersection with any other task is `[]`.
2. No conflict is reported for this pair.

## Failure Flows

### F1: All in-progress tasks have non-overlapping files
Condition: No two in-progress tasks share a file path.
Steps:
1. All pair intersections are empty.
2. `state.file_conflicts` is `[]`.
Result: No false positives; dashboard shows no conflict warnings.

## Gherkin Scenarios

### S1: Two tasks sharing a file are detected as conflicting
```gherkin
Scenario: Two in-progress tasks with a shared file produce a conflict entry
  Given task A is in_progress with files ["lib/foo.ex", "lib/bar.ex"]
  And task B is in_progress with files ["lib/bar.ex"]
  When detect_file_conflicts/1 runs
  Then state.file_conflicts contains {A.id, B.id, ["lib/bar.ex"]}
```

### S2: Each pair is reported only once
```gherkin
Scenario: The same pair of tasks is reported only once regardless of ID order
  Given task "1" and task "2" both claim "lib/foo.ex"
  When detect_file_conflicts/1 runs
  Then state.file_conflicts contains exactly one entry for this pair
  And the entry uses the smaller ID first
```

### S3: Tasks with empty files lists produce no conflict
```gherkin
Scenario: In-progress tasks with empty files lists do not conflict
  Given task A is in_progress with files []
  And task B is in_progress with files []
  When detect_file_conflicts/1 runs
  Then state.file_conflicts is empty
```

### S4: Pending tasks are excluded from conflict detection
```gherkin
Scenario: Pending and completed tasks are not checked for file conflicts
  Given task A is pending with files ["lib/foo.ex"]
  And task B is in_progress with files ["lib/foo.ex"]
  When detect_file_conflicts/1 runs
  Then state.file_conflicts is empty
```

## Acceptance Criteria
- [ ] A unit test with task A (files: `["lib/foo.ex", "lib/bar.ex"]`, in_progress) and task B (files: `["lib/bar.ex"]`, in_progress) asserts `state.file_conflicts == [{"A_id", "B_id", ["lib/bar.ex"]}]` (S1).
- [ ] A unit test with three in-progress tasks sharing the same file asserts three distinct conflict entries, one per pair (S2).
- [ ] A unit test with two in-progress tasks and empty `files` lists asserts `state.file_conflicts == []` (S3).
- [ ] A unit test with one pending and one in-progress task sharing a file asserts `state.file_conflicts == []` (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `state.tasks` -- normalised task maps; each task's `id`, `status`, and `files` fields
**Outputs:** `state.file_conflicts` -- list of `{id_a, id_b, [shared_paths]}` tuples
**State changes:** `state.file_conflicts` replaced on every poll cycle

## Traceability
- Parent FR: [FR-4.8](../frds/FRD-004-swarm-monitor-protocol-tracker.md)
- ADR: [ADR-007](../../decisions/ADR-007-swarm-monitor-design.md)
