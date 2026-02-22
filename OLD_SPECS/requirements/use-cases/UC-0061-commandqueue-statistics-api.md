---
id: UC-0061
title: Query CommandQueue Pending File Statistics
status: draft
parent_fr: FR-3.12
adrs: [ADR-005]
---

# UC-0061: Query CommandQueue Pending File Statistics

## Intent
`Observatory.CommandQueue.get_queue_stats/0` scans the `~/.claude/inbox/` directory tree and returns per-session statistics for any session subdirectory that contains at least one `.json` file. Each result includes the session ID, the count of pending files, and the age of the oldest file. Sessions with no pending files are excluded, enabling operators to identify agents with unprocessed message queues (indicative of a dead or stalled agent).

## Primary Actor
`Observatory.CommandQueue` (module-level function or GenServer call)

## Supporting Actors
- `~/.claude/inbox/` filesystem directory

## Preconditions
- `~/.claude/inbox/` exists (initialized by `CommandQueue.init/1` per FR-3.10).
- At least one session subdirectory contains `.json` files.

## Trigger
A caller invokes `Observatory.CommandQueue.get_queue_stats()`.

## Main Success Flow
1. `get_queue_stats/0` lists all subdirectories of `~/.claude/inbox/`.
2. For each subdirectory (session ID), it lists all `.json` files.
3. If `pending_count == 0`, the session is excluded from the result.
4. For sessions with at least one file, it computes:
   - `pending_count`: number of `.json` files in the directory.
   - `oldest_age_sec`: `System.os_time(:second) - oldest_file_mtime_sec` where `oldest_file_mtime_sec` is the earliest mtime among all `.json` files.
5. It returns a list of maps, one per qualifying session.

## Alternate Flows

### A1: No sessions have pending files
Condition: All session subdirectories under `~/.claude/inbox/` are empty or contain no `.json` files.
Steps:
1. Every session is excluded (pending_count == 0).
2. `get_queue_stats/0` returns `[]`.

### A2: Session directory contains only non-JSON files
Condition: A session directory has files but none end in `.json`.
Steps:
1. `pending_count` is computed as 0 (only `.json` files are counted).
2. The session is excluded from the result.

## Failure Flows

### F1: Sessions with pending_count == 0 included in result
Condition: The filter for `pending_count > 0` is absent.
Steps:
1. Every session that has ever received a message appears in the result (with `pending_count: 0`).
2. The result contains noise entries for all historical sessions.
3. Operators cannot distinguish sessions with actual unprocessed queues.
Result: Stat API unusable for dead-agent detection.

### F2: Inbox base directory does not exist
Condition: `~/.claude/inbox/` was not initialized (FR-3.10 violated).
Steps:
1. `File.ls!/1` raises `File.Error` for the missing directory.
2. `get_queue_stats/0` crashes.
Result: Stat API non-functional; CallerSSS receives an exception.

## Gherkin Scenarios

### S1: Session with pending files appears in stats
```gherkin
Scenario: get_queue_stats returns stats for session with pending JSON files
  Given 10 JSON files exist in ~/.claude/inbox/agent-x/
  And no files have been acknowledged (none deleted)
  When Observatory.CommandQueue.get_queue_stats() is called
  Then the result contains %{session_id: "agent-x", pending_count: 10, oldest_age_sec: age}
  And age is a non-negative integer
```

### S2: Session with no pending files is excluded
```gherkin
Scenario: get_queue_stats excludes sessions with no pending JSON files
  Given ~/.claude/inbox/agent-y/ exists but contains no JSON files
  When Observatory.CommandQueue.get_queue_stats() is called
  Then the result does NOT contain any entry with session_id: "agent-y"
```

### S3: Empty inbox returns empty list
```gherkin
Scenario: get_queue_stats returns [] when no sessions have pending files
  Given ~/.claude/inbox/ has no subdirectories with JSON files
  When Observatory.CommandQueue.get_queue_stats() is called
  Then the result is []
```

## Acceptance Criteria
- [ ] `mix test` passes a test that writes 10 files to `~/.claude/inbox/agent-x/` with `.json` extension, calls `CommandQueue.get_queue_stats()`, and asserts the result contains `%{session_id: "agent-x", pending_count: 10, oldest_age_sec: age}` where `age >= 0` (S1).
- [ ] The same test asserts a separate session directory with no `.json` files does NOT appear in the result (S2).
- [ ] A test with an empty inbox asserts `get_queue_stats()` returns `[]` (S3).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** None (reads `~/.claude/inbox/` filesystem directly).
**Outputs:** `[%{session_id: string, pending_count: non_neg_integer, oldest_age_sec: non_neg_integer}]` — only sessions with `pending_count > 0`.
**State changes:** None (read-only filesystem scan).

## Traceability
- Parent FR: [FR-3.12](../frds/FRD-003-messaging-pipeline.md)
- ADR: [ADR-005](../../decisions/ADR-005-ets-over-database.md)
