---
id: UC-0058
title: Poll CommandQueue Outbox for Agent Response Files
status: draft
parent_fr: FR-3.9
adrs: [ADR-005]
---

# UC-0058: Poll CommandQueue Outbox for Agent Response Files

## Intent
The `Observatory.CommandQueue` GenServer polls `~/.claude/outbox/{session_id}/` directories every 2 seconds for JSON response files written by agents. When files are found, they are decoded and broadcast on the corresponding PubSub session topic, then deleted. Malformed files are logged and left in place to allow operator inspection, preventing silent data loss.

## Primary Actor
`Observatory.CommandQueue` GenServer

## Supporting Actors
- `Phoenix.PubSub` (`Observatory.PubSub`)
- `~/.claude/outbox/` filesystem directory

## Preconditions
- `Observatory.CommandQueue` is running with `~/.claude/outbox/` initialized.
- The outbox poll timer is scheduled via `Process.send_after(self(), :poll_outbox, 2000)` during `init/1`.

## Trigger
The GenServer receives the `:poll_outbox` message, fired every 2000 milliseconds.

## Main Success Flow
1. The GenServer receives `handle_info(:poll_outbox, state)`.
2. It lists all subdirectories under `~/.claude/outbox/` to obtain session IDs.
3. For each session directory, it lists `*.json` files.
4. For each file, it reads the file contents and calls `Jason.decode!/1`.
5. It collects all decoded maps for the session into a list.
6. It calls `Phoenix.PubSub.broadcast(Observatory.PubSub, "session:#{session_id}", {:command_responses, [decoded_map, ...]})`.
7. It deletes each successfully decoded file via `File.rm/1`.
8. It reschedules the next poll: `Process.send_after(self(), :poll_outbox, 2000)`.
9. The GenServer returns `{:noreply, state}`.

## Alternate Flows

### A1: No files present in outbox
Condition: All session directories under `~/.claude/outbox/` are empty or absent.
Steps:
1. The file listing returns empty for all sessions.
2. No PubSub broadcasts are made.
3. The poll reschedules normally.

## Failure Flows

### F1: JSON decoding fails for a malformed file
Condition: A file at `~/.claude/outbox/{session_id}/resp-001.json` contains invalid JSON.
Steps:
1. `Jason.decode!/1` raises `Jason.DecodeError`.
2. The GenServer catches the error and logs it at error level.
3. The file is NOT deleted.
4. Processing continues for other files in the same or other session directories.
Result: The malformed file remains in the outbox for operator inspection; no data loss.

### F2: Poll timer not rescheduled
Condition: `Process.send_after(self(), :poll_outbox, 2000)` is not called at the end of `handle_info(:poll_outbox, state)`.
Steps:
1. The outbox is polled once after startup.
2. No subsequent polls occur.
3. Agent response files accumulate in `~/.claude/outbox/` indefinitely.
Result: Dashboard never receives agent responses; real-time command-response loop breaks.

### F3: File deleted before decoding
Condition: A code change deletes the file before calling `Jason.decode!/1`.
Steps:
1. A malformed JSON file is deleted.
2. No PubSub broadcast is made for it.
3. No error is logged.
Result: Malformed file is permanently lost with no opportunity for inspection.

## Gherkin Scenarios

### S1: Valid response file decoded and broadcast
```gherkin
Scenario: CommandQueue polls outbox, decodes file, and broadcasts on session topic
  Given a file exists at ~/.claude/outbox/abc123/resp-001.json with valid JSON content
  And a process is subscribed to "session:abc123"
  When the :poll_outbox handler fires
  Then the process receives {:command_responses, [decoded_map]}
  And the file ~/.claude/outbox/abc123/resp-001.json is deleted
```

### S2: Malformed JSON file is logged and retained
```gherkin
Scenario: Malformed outbox file is not deleted and is logged as error
  Given a file exists at ~/.claude/outbox/abc123/bad.json with content "not-json"
  When the :poll_outbox handler fires
  Then an error is logged referencing the file path
  And the file ~/.claude/outbox/abc123/bad.json still exists
  And no PubSub broadcast is made for this file
```

### S3: Empty outbox produces no broadcasts
```gherkin
Scenario: Poll with empty outbox directories completes without error
  Given ~/.claude/outbox/ contains no JSON files in any session directory
  When the :poll_outbox handler fires
  Then no PubSub broadcast is made
  And the GenServer returns {:noreply, state} without error
```

### S4: Poll reschedules itself
```gherkin
Scenario: Poll handler reschedules next poll after completion
  When the :poll_outbox handler completes
  Then a new :poll_outbox message is scheduled via Process.send_after with 2000 ms delay
```

## Acceptance Criteria
- [ ] `mix test` passes a test that writes a valid JSON file to `~/.claude/outbox/test-session/resp-001.json`, subscribes to `"session:test-session"`, sends `:poll_outbox` to the CommandQueue GenServer, and asserts `assert_receive {:command_responses, [_]}` and that the file no longer exists (S1).
- [ ] A test writes an invalid JSON file, sends `:poll_outbox`, and asserts the file still exists afterward (S2).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** JSON files at `~/.claude/outbox/{session_id}/*.json`.
**Outputs:** `{:command_responses, [map, ...]}` broadcast on `"session:#{session_id}"`; files deleted after successful decode.
**State changes:** Outbox files deleted on successful decode; malformed files left in place.

## Traceability
- Parent FR: [FR-3.9](../frds/FRD-003-messaging-pipeline.md)
- ADR: [ADR-005](../../decisions/ADR-005-ets-over-database.md)
