---
id: UC-0059
title: Initialize CommandQueue Filesystem Directories on Startup
status: draft
parent_fr: FR-3.10
adrs: [ADR-005]
---

# UC-0059: Initialize CommandQueue Filesystem Directories on Startup

## Intent
During `init/1`, the `Observatory.CommandQueue` GenServer creates both `~/.claude/inbox/` and `~/.claude/outbox/` base directories if they do not exist. This guarantees that subsequent `write_command/2` calls and outbox polling operations never fail due to a missing parent directory, regardless of whether Observatory has been run on this machine before.

## Primary Actor
`Observatory.CommandQueue` GenServer

## Supporting Actors
- `File.mkdir_p!/1` (filesystem)

## Preconditions
- The `Observatory.CommandQueue` GenServer supervision tree is starting.
- `~/.claude/` exists (standard Claude Code installation directory).

## Trigger
`Observatory.CommandQueue.init/1` is called by the OTP supervisor during application startup.

## Main Success Flow
1. `init/1` calls `File.mkdir_p!(Path.expand("~/.claude/inbox"))`.
2. `init/1` calls `File.mkdir_p!(Path.expand("~/.claude/outbox"))`.
3. Both directories are created if absent, or left unchanged if they already exist.
4. `init/1` schedules the outbox poll timer and returns `{:ok, initial_state}`.
5. Subsequent `write_command/2` calls create per-session subdirectories (`~/.claude/inbox/{session_id}/`) without needing to create the parent first.

## Alternate Flows

### A1: Directories already exist
Condition: Both `~/.claude/inbox/` and `~/.claude/outbox/` exist from a prior Observatory run.
Steps:
1. `File.mkdir_p!/1` is idempotent — it succeeds without modifying the existing directories.
2. Startup proceeds normally.

## Failure Flows

### F1: Directories not created during init
Condition: The `ensure_directories/0` (or equivalent) call is absent from `init/1`.
Steps:
1. The GenServer starts successfully.
2. The first `write_command/2` call for a new agent attempts to write to `~/.claude/inbox/{session_id}/`.
3. `File.mkdir_p!("~/.claude/inbox/#{session_id}")` fails because the parent `~/.claude/inbox/` does not exist.
4. The `write_command/2` call raises or returns an error.
Result: The first message sent to each new agent is silently dropped from the filesystem channel. ETS and PubSub delivery still proceed, creating a channel inconsistency.

### F2: ~/.claude/ does not exist
Condition: Claude Code has never been installed on the machine.
Steps:
1. `File.mkdir_p!/1` attempts to create `~/.claude/inbox/` — `mkdir_p!` creates all intermediate directories, so `~/.claude/` is also created.
2. Startup proceeds (though Claude Code itself will not function without proper installation).

## Gherkin Scenarios

### S1: Directories created on fresh install
```gherkin
Scenario: CommandQueue init creates inbox and outbox directories if absent
  Given ~/.claude/inbox/ does not exist
  And ~/.claude/outbox/ does not exist
  When the Observatory.CommandQueue GenServer starts
  Then File.exists?(Path.expand("~/.claude/inbox")) is true
  And File.exists?(Path.expand("~/.claude/outbox")) is true
```

### S2: Existing directories are not modified
```gherkin
Scenario: CommandQueue init is idempotent when directories already exist
  Given ~/.claude/inbox/ already exists with a file inside
  When the Observatory.CommandQueue GenServer starts
  Then the existing file inside ~/.claude/inbox/ is undisturbed
  And no error is raised
```

### S3: Missing init call causes write_command to fail
```gherkin
Scenario: Absent directory initialization causes first write_command to fail
  Given ~/.claude/inbox/ does not exist
  And ensure_directories/0 was not called in init/1
  When Observatory.CommandQueue.write_command("new-agent", %{type: "message"}) is called
  Then the call raises or returns an error
  And no JSON file is created for "new-agent"
```

## Acceptance Criteria
- [ ] `mix test` passes a test that removes `~/.claude/inbox/` and `~/.claude/outbox/` in test setup, starts a `CommandQueue` GenServer, and asserts both directories exist after `init/1` completes (S1).
- [ ] The same test asserts that a subsequent `write_command("new-agent", %{type: "message", content: "hello"})` succeeds and creates `~/.claude/inbox/new-agent/{id}.json` (verifying the parent directory exists) (S1).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** None (called unconditionally during `init/1`).
**Outputs:** `~/.claude/inbox/` and `~/.claude/outbox/` directories exist on the filesystem.
**State changes:** Filesystem directories created if absent; no ETS or GenServer state change.

## Traceability
- Parent FR: [FR-3.10](../frds/FRD-003-messaging-pipeline.md)
- ADR: [ADR-005](../../decisions/ADR-005-ets-over-database.md)
