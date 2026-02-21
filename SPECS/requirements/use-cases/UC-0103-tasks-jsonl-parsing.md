---
id: UC-0103
title: Parse and normalise tasks.jsonl into task structs
status: draft
parent_fr: FR-4.4
adrs: [ADR-007]
---

# UC-0103: Parse and Normalise tasks.jsonl into Task Structs

## Intent
When a `tasks.jsonl` file exists for the active project, SwarmMonitor streams it line by line, decodes each line as JSON, applies field defaults, rejects deleted and malformed entries, and produces a normalised list of task maps that feeds all downstream aggregation (pipeline counts, DAG, stale detection).

## Primary Actor
`Observatory.SwarmMonitor`

## Supporting Actors
- File system (`<project-root>/tasks.jsonl`)
- `Jason.decode/1` JSON parser

## Preconditions
- `state.active_project` is non-nil and points to an existing directory.
- The `:poll_tasks` cycle is executing.

## Trigger
`handle_info(:poll_tasks, state)` invokes the internal `read_tasks/1` function with the active project path.

## Main Success Flow
1. SwarmMonitor checks that `<project-root>/tasks.jsonl` exists.
2. The file is streamed line by line.
3. Each non-empty line is decoded with `Jason.decode/1`; failures produce `nil`.
4. `nil` results are rejected via `Enum.reject(&is_nil/1)`.
5. Tasks with `status == "deleted"` are rejected.
6. Remaining maps are normalised: string fields (`id`, `status`, `subject`, `description`, `owner`, `priority`, `done_when`, `notes`) default to `""`; list fields (`blocked_by`, `files`, `tags`) default to `[]`; `updated` falls back to `created` when absent.
7. The normalised list is stored in `state.tasks`.

## Alternate Flows

### A1: tasks.jsonl does not exist
Condition: `File.exists?/1` returns false for the expected path.
Steps:
1. `read_tasks/1` returns an empty list.
2. `state.tasks` is set to `[]`.
3. All pipeline aggregates are 0; DAG is empty; no stale tasks.

### A2: tasks.jsonl is empty
Condition: The file exists but contains no non-empty lines.
Steps:
1. Streaming produces no lines.
2. `state.tasks` is `[]`; processing continues normally with empty aggregates.

## Failure Flows

### F1: A line contains malformed JSON
Condition: `Jason.decode/1` returns `{:error, _}` for a line.
Steps:
1. The result for that line is `nil`.
2. `Enum.reject(&is_nil/1)` removes it from the list.
3. All other lines are processed normally.
Result: The malformed line is silently skipped; no crash occurs and the task list is partial.

## Gherkin Scenarios

### S1: Well-formed tasks.jsonl produces normalised task list
```gherkin
Scenario: Valid tasks.jsonl is parsed into normalised task maps
  Given tasks.jsonl contains a line {"id":"1","status":"in_progress","subject":"Fix bug","updated":"2026-02-21T12:00:00Z","files":["lib/foo.ex"]}
  When the :poll_tasks cycle reads the file
  Then state.tasks contains a map with id "1", status "in_progress", and files ["lib/foo.ex"]
  And absent fields such as owner and priority default to ""
  And absent list fields such as blocked_by and tags default to []
```

### S2: Deleted tasks are excluded
```gherkin
Scenario: Tasks with status deleted are excluded from the normalised list
  Given tasks.jsonl contains two lines: one with status "pending" and one with status "deleted"
  When the :poll_tasks cycle reads the file
  Then state.tasks contains only the pending task
  And the deleted task is absent from state.tasks
```

### S3: Malformed JSON line is skipped
```gherkin
Scenario: A malformed JSON line does not crash parsing
  Given tasks.jsonl contains one valid line and one line with invalid JSON
  When the :poll_tasks cycle reads the file
  Then state.tasks contains the one valid task
  And no error is raised
```

### S4: Missing file produces empty task list
```gherkin
Scenario: Absent tasks.jsonl yields empty task list
  Given the active project directory contains no tasks.jsonl file
  When the :poll_tasks cycle executes
  Then state.tasks is an empty list
  And state.pipeline.total is 0
```

## Acceptance Criteria
- [ ] A unit test providing a two-line `tasks.jsonl` (one valid, one with `status: "deleted"`) asserts `length(state.tasks) == 1` (S2).
- [ ] A unit test providing a file with one valid line and one malformed JSON line asserts `length(state.tasks) == 1` and no exception is raised (S3).
- [ ] A unit test with a missing file path asserts `state.tasks == []` (S4).
- [ ] A unit test verifying that a task missing `updated` uses the `created` field as fallback (S1).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Absolute path to `tasks.jsonl`; file contents as line-delimited JSON
**Outputs:** `state.tasks` -- list of normalised task maps with all required keys present
**State changes:** `state.tasks` replaced on every poll cycle

## Traceability
- Parent FR: [FR-4.4](../frds/FRD-004-swarm-monitor-protocol-tracker.md)
- ADR: [ADR-007](../../decisions/ADR-007-swarm-monitor-design.md)
