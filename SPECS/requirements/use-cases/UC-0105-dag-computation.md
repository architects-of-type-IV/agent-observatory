---
id: UC-0105
title: Compute DAG waves, edges, and critical path from task dependencies
status: draft
parent_fr: FR-4.6
adrs: [ADR-007]
---

# UC-0105: Compute DAG Waves, Edges, and Critical Path from Task Dependencies

## Intent
SwarmMonitor derives a dependency graph from each task's `blocked_by` list and computes three derived structures: `edges` (direct dependency pairs), `waves` (topological layers for parallel scheduling), and `critical_path` (the longest dependency chain). These structures drive the Pipeline DAG visualisation on the dashboard.

## Primary Actor
`Observatory.SwarmMonitor`

## Supporting Actors
- `state.tasks` (normalised task list from UC-0103)
- Internal `compute_dag/1`, `compute_waves/2`, and `compute_critical_path/2` functions

## Preconditions
- `state.tasks` is available after the current poll cycle's parsing step.

## Trigger
`handle_info(:poll_tasks, state)` calls `compute_dag(tasks)` after `aggregate_pipeline/1` completes.

## Main Success Flow
1. `edges` is built: for each task, for each entry in `task.blocked_by`, a tuple `{blocker_id, task.id}` is appended to the list.
2. Wave 0 is seeded with task IDs that have an empty `blocked_by` list.
3. Iterative topological sort assigns each remaining task to the earliest wave in which all its blockers appear; the loop terminates when no new tasks are assignable or 50 iterations are reached.
4. Tasks that remain unassigned after 50 iterations (circular dependencies) are placed in a final terminal wave.
5. `critical_path` is computed via memoised DFS: starting from each root task (wave 0), the longest path through the edge graph is tracked; the longest overall path is stored.
6. The `dag` map `%{waves: [[ids], ...], edges: [{id, id}, ...], critical_path: [ids]}` is stored in `state.dag`.

## Alternate Flows

### A1: No dependencies in task list
Condition: All tasks have empty `blocked_by` lists.
Steps:
1. All task IDs appear in wave 0.
2. `edges` is `[]`.
3. `critical_path` is `[]` (no dependency chains to traverse).

### A2: Circular dependency between two tasks
Condition: Task A has `blocked_by: ["B"]` and task B has `blocked_by: ["A"]`.
Steps:
1. Neither A nor B can be placed in any wave via normal topological sort.
2. After 50 iterations, both are collected into a terminal wave.
3. An edge pair `{B, A}` and `{A, B}` appears in `edges`.
4. `critical_path` omits the circular pair.

## Failure Flows

### F1: tasks list is empty
Condition: `state.tasks` is `[]`.
Steps:
1. `edges` is `[]`, `waves` is `[]`, `critical_path` is `[]`.
2. `state.dag` is `%{waves: [], edges: [], critical_path: []}`.
Result: Dashboard renders an empty DAG without error.

## Gherkin Scenarios

### S1: Linear chain produces correct waves and critical path
```gherkin
Scenario: Linear dependency chain A -> B -> C produces three waves and a matching critical path
  Given tasks A (no deps), B (blocked_by A), and C (blocked_by B)
  When compute_dag/1 runs
  Then state.dag.waves is [["A"], ["B"], ["C"]]
  And state.dag.edges contains {A, B} and {B, C}
  And state.dag.critical_path is ["A", "B", "C"]
```

### S2: Diamond dependency produces correct waves
```gherkin
Scenario: Diamond dependency A -> B and A -> C, both -> D produces three waves
  Given tasks A (no deps), B (blocked_by A), C (blocked_by A), D (blocked_by B and C)
  When compute_dag/1 runs
  Then wave 0 contains A
  And wave 1 contains B and C
  And wave 2 contains D
```

### S3: Circular dependency does not cause infinite loop
```gherkin
Scenario: Circular dependency is placed in a terminal wave after iteration cap
  Given task A has blocked_by ["B"] and task B has blocked_by ["A"]
  When compute_dag/1 runs
  Then compute_dag returns without error
  And A and B appear in a terminal wave
  And the iteration did not exceed 50 cycles
```

### S4: No dependencies places all tasks in wave 0
```gherkin
Scenario: Tasks with no blocked_by all appear in wave 0
  Given three tasks each with an empty blocked_by list
  When compute_dag/1 runs
  Then state.dag.waves has exactly one wave containing all three task IDs
  And state.dag.edges is empty
```

## Acceptance Criteria
- [ ] A unit test with tasks A, B (blocked_by A), C (blocked_by B) asserts `waves == [["A"], ["B"], ["C"]]` and `critical_path == ["A", "B", "C"]` (S1).
- [ ] A unit test with a circular pair (A blocked_by B, B blocked_by A) returns without raising and places both in a non-wave-0 list (S3).
- [ ] A unit test with three independent tasks asserts `length(hd(waves)) == 3` (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `state.tasks` list; each task's `id` and `blocked_by` fields
**Outputs:** `state.dag` map with `waves`, `edges`, and `critical_path`
**State changes:** `state.dag` replaced on every poll cycle

## Traceability
- Parent FR: [FR-4.6](../frds/FRD-004-swarm-monitor-protocol-tracker.md)
- ADR: [ADR-007](../../decisions/ADR-007-swarm-monitor-design.md)
