---
id: UC-0109
title: Execute operational actions on tasks via SwarmMonitor client API
status: draft
parent_fr: FR-4.10
adrs: [ADR-007]
---

# UC-0109: Execute Operational Actions on Tasks via SwarmMonitor Client API

## Intent
The dashboard and swarm lead can invoke operational actions against `tasks.jsonl` through SwarmMonitor's client API: healing a stuck task, reassigning ownership, resetting all stale tasks, triggering GC, claiming a task, switching the active project, or adding a project manually. Every mutation action refreshes state and broadcasts to the dashboard.

## Primary Actor
`Observatory.SwarmMonitor`

## Supporting Actors
- `tasks.jsonl` file (via `jq` shell commands)
- `~/.claude/skills/dag/scripts/gc.sh` and `claim-task.sh` scripts
- `ObservatoryWeb.DashboardLive` (receives broadcast after each mutation)

## Preconditions
- SwarmMonitor is running with a non-nil `active_project`.
- `tasks.jsonl` exists at the active project path (for mutation actions).

## Trigger
Dashboard user invokes an action (e.g., "Heal Task", "Reset All Stale") which calls the corresponding `SwarmMonitor` client function.

## Main Success Flow
1. The client calls `SwarmMonitor.heal_task("3")`.
2. SwarmMonitor calls `GenServer.call(SwarmMonitor, {:heal_task, "3"})`.
3. The handler constructs a `jq` command that sets the task's `status` to `"pending"` and `owner` to `""`.
4. `System.cmd("jq", [...])` executes the in-place mutation on `tasks.jsonl`.
5. `refresh_tasks/1` is called to reload `state.tasks` and recompute all aggregates.
6. `broadcast/1` sends `{:swarm_state, state}` on `"swarm:update"`.
7. The call returns `:ok`.

## Alternate Flows

### A1: reset_all_stale with configurable threshold
Condition: `reset_all_stale(threshold_min: 5)` is called.
Steps:
1. SwarmMonitor uses 5 minutes instead of 10 for stale detection.
2. All tasks with `status == "in_progress"` and age > 5 minutes are reset to `"pending"` with cleared owner.
3. Returns `{:ok, count}` where `count` is the number of tasks reset.

### A2: set_active_project to a known key
Condition: `set_active_project("other-project")` is called and the key exists in `watched_projects`.
Steps:
1. `state.active_project` is updated.
2. `refresh_tasks/1` reads the new project's `tasks.jsonl`.
3. Broadcast delivers updated state.

### A3: add_project with valid path
Condition: `add_project("new-key", "/abs/path/to/project")` is called and the path exists.
Steps:
1. `watched_projects` gains the new entry.
2. No broadcast is issued immediately; the next poll cycle picks up the project.

## Failure Flows

### F1: Action called with nil active_project
Condition: `state.active_project` is `nil` when a mutation action is called.
Steps:
1. The action returns `{:error, :no_active_project}` immediately.
2. No file write is attempted.
3. State and broadcast are unchanged.

### F2: jq command fails
Condition: `System.cmd("jq", [...])` returns a non-zero exit code.
Steps:
1. The action returns `{:error, reason_string}`.
2. `refresh_tasks/1` is still called to sync state with the actual file contents.
3. Broadcast delivers current (possibly unchanged) state.

### F3: set_active_project with unknown key
Condition: The requested key is not in `watched_projects`.
Steps:
1. Returns `{:error, :unknown_project}`.
2. `state.active_project` is unchanged.

## Gherkin Scenarios

### S1: heal_task resets a task to pending
```gherkin
Scenario: heal_task resets status to pending and clears owner
  Given a task with id "3" has status "in_progress" and owner "worker-a"
  When SwarmMonitor.heal_task("3") is called
  Then tasks.jsonl is updated: task "3" has status "pending" and owner ""
  And a {:swarm_state, state} message is broadcast on "swarm:update"
  And the call returns :ok
```

### S2: reset_all_stale returns count of reset tasks
```gherkin
Scenario: reset_all_stale resets all in-progress tasks older than threshold
  Given two tasks are in_progress with updated timestamps older than 10 minutes
  When SwarmMonitor.reset_all_stale([]) is called
  Then both tasks are reset to status "pending" with cleared owner
  And the call returns {:ok, 2}
```

### S3: Action with nil active_project returns error
```gherkin
Scenario: Mutation action with no active project returns error without file write
  Given SwarmMonitor.get_state().active_project is nil
  When SwarmMonitor.heal_task("1") is called
  Then the call returns {:error, :no_active_project}
  And tasks.jsonl is not modified
```

### S4: set_active_project with unknown key returns error
```gherkin
Scenario: set_active_project with unknown key is rejected
  Given watched_projects does not contain key "nonexistent"
  When SwarmMonitor.set_active_project("nonexistent") is called
  Then the call returns {:error, :unknown_project}
  And state.active_project is unchanged
```

## Acceptance Criteria
- [ ] A test calling `heal_task/1` on a task with `status: "in_progress"` asserts the task line in `tasks.jsonl` has `status: "pending"` and `owner: ""` after the call (S1).
- [ ] A test with two stale in-progress tasks asserts `reset_all_stale([])` returns `{:ok, 2}` and both tasks show `status: "pending"` in the file (S2).
- [ ] A test with `active_project: nil` asserts `heal_task("1")` returns `{:error, :no_active_project}` (S3).
- [ ] A test asserts `set_active_project("unknown")` returns `{:error, :unknown_project}` (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Task ID strings; optional threshold integers; project key and path strings
**Outputs:** `:ok`, `{:ok, count}`, or `{:error, reason}` return values; updated `tasks.jsonl` contents
**State changes:** `tasks.jsonl` mutated in-place; `state.tasks` refreshed; broadcast delivered

## Traceability
- Parent FR: [FR-4.10](../frds/FRD-004-swarm-monitor-protocol-tracker.md)
- ADR: [ADR-007](../../decisions/ADR-007-swarm-monitor-design.md)
