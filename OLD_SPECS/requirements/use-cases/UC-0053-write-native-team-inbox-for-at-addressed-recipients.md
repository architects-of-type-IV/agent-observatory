---
id: UC-0053
title: Write Native Team Inbox for At-Addressed Recipients
status: draft
parent_fr: FR-3.4
adrs: [ADR-004]
---

# UC-0053: Write Native Team Inbox for At-Addressed Recipients

## Intent
When a message is addressed to a recipient whose session ID contains an `@` character (format: `"agent_name@team_name"`), `Mailbox.send_message/4` additionally writes the message in Claude Code native format to `~/.claude/teams/{team_name}/inboxes/{agent_name}.json`. This ensures agents polling via Claude Code's native team messaging mechanism receive dashboard messages alongside those arriving through the custom CommandQueue inbox.

## Primary Actor
`Observatory.Mailbox` GenServer

## Supporting Actors
- `Observatory.CommandQueue` GenServer (native write via `write_team_message/3`)
- `~/.claude/teams/{team_name}/inboxes/` filesystem directory

## Preconditions
- `Observatory.Mailbox` and `Observatory.CommandQueue` GenServers are running.
- The `~/.claude/teams/{team_name}/` directory exists (created by Claude Code team tooling, not Observatory).
- The recipient `to` parameter is a string containing exactly one `@` character.

## Trigger
A caller invokes `Observatory.Mailbox.send_message("worker@my-team", from, content, opts)`.

## Main Success Flow
1. `Mailbox.send_message/4` detects the `@` character in the `to` parameter.
2. It splits the string into `agent_name = "worker"` and `team_name = "my-team"`.
3. It performs the standard dual-write (ETS + CommandQueue inbox file at `~/.claude/inbox/worker@my-team/{id}.json`) as per FR-3.3.
4. It additionally calls `CommandQueue.write_team_message("my-team", "worker", message_params)`.
5. `write_team_message/3` reads the existing `~/.claude/teams/my-team/inboxes/worker.json` array (or starts with `[]` if absent).
6. It appends a native format entry: `{"from": from, "text": content, "timestamp": "<ISO 8601>", "read": false}`.
7. It writes the updated JSON array back to `~/.claude/teams/my-team/inboxes/worker.json`.
8. `Mailbox.send_message/4` returns `{:ok, message}`.

## Alternate Flows

### A1: Native inbox file does not yet exist
Condition: `~/.claude/teams/my-team/inboxes/worker.json` has not been created before.
Steps:
1. `write_team_message/3` treats the initial array as `[]`.
2. The new entry is the sole element; the file is written with `[{"from": ..., "text": ..., ...}]`.

### A2: Recipient without @ is not affected
Condition: The `to` parameter has no `@` character (e.g., `"agent-42"`).
Steps:
1. `Mailbox.send_message/4` performs only the standard dual-write (ETS + CommandQueue).
2. No native team inbox file is written.

## Failure Flows

### F1: @ parsing omitted — native team inbox not written
Condition: The `@` detection logic is absent; the code treats all recipients identically.
Steps:
1. The standard dual-write proceeds (ETS + CommandQueue custom file).
2. `~/.claude/teams/my-team/inboxes/worker.json` is not updated.
3. Agents using Claude Code's native SendMessage polling never see the message.
Result: Re-introduces the split inbox bug documented in ADR-004 — the original root cause of the messaging architecture redesign.

### F2: Native inbox directory does not exist
Condition: `~/.claude/teams/my-team/inboxes/` has not been created.
Steps:
1. `CommandQueue.write_team_message/3` attempts to write and encounters a `File.Error` for missing parent directory.
2. The standard ETS + CommandQueue writes have already completed.
Result: Partial delivery — custom inbox file exists but native inbox is not updated. Error is logged; no crash.

## Gherkin Scenarios

### S1: Native inbox written for at-addressed recipient
```gherkin
Scenario: Message to "worker@my-team" is written to both inboxes
  Given ~/.claude/teams/my-team/inboxes/ directory exists
  And ~/.claude/teams/my-team/inboxes/worker.json contains []
  When Observatory.Mailbox.send_message("worker@my-team", "dashboard", "task done", []) is called
  Then ~/.claude/inbox/worker@my-team/{id}.json exists (custom format)
  And ~/.claude/teams/my-team/inboxes/worker.json contains one entry
  And the entry has fields: from, text, timestamp (ISO 8601), read: false
```

### S2: Non-at recipient is unaffected
```gherkin
Scenario: Message to plain session ID does not write native team inbox
  Given the recipient is "agent-42" (no @ character)
  When Observatory.Mailbox.send_message("agent-42", "dashboard", "hello", []) is called
  Then ~/.claude/inbox/agent-42/{id}.json exists
  And no file under ~/.claude/teams/ is written or modified
```

### S3: Subsequent messages are appended to native inbox array
```gherkin
Scenario: Second message to "worker@my-team" appends to existing array
  Given ~/.claude/teams/my-team/inboxes/worker.json already contains one entry
  When Observatory.Mailbox.send_message("worker@my-team", "dashboard", "second msg", []) is called
  Then ~/.claude/teams/my-team/inboxes/worker.json contains two entries
  And the second entry is the newest message
```

## Acceptance Criteria
- [ ] `mix test` passes a test that calls `Mailbox.send_message("worker@my-team", "dashboard", "task done", [])` and asserts `~/.claude/teams/my-team/inboxes/worker.json` contains a JSON array with one entry having `"from"`, `"text"`, `"timestamp"`, and `"read": false` fields (S1).
- [ ] The same test asserts `~/.claude/inbox/worker@my-team/{id}.json` also exists (custom channel still written) (S1).
- [ ] A test asserts that `Mailbox.send_message("agent-42", "dashboard", "hello", [])` does NOT write to any file under `~/.claude/teams/` (S2).
- [ ] A test asserts that a second `send_message` call for the same `worker@my-team` recipient appends to the existing array rather than overwriting it (S3).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `to` string containing `@` (e.g., `"agent_name@team_name"`), `from` (string), `content` (string), `opts` keyword list.
**Outputs:** `{:ok, message}`; ETS entry; custom CommandQueue file; native team inbox entry appended.
**State changes:** `~/.claude/inbox/{to}/{id}.json` created; `~/.claude/teams/{team}/inboxes/{agent}.json` array appended.

## Traceability
- Parent FR: [FR-3.4](../frds/FRD-003-messaging-pipeline.md)
- ADR: [ADR-004](../../decisions/ADR-004-messaging-architecture.md)
