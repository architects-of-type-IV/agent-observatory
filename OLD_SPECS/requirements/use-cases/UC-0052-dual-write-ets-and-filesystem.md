---
id: UC-0052
title: Dual-Write Message to ETS and Filesystem on Every Send
status: draft
parent_fr: FR-3.3
adrs: [ADR-004, ADR-005]
---

# UC-0052: Dual-Write Message to ETS and Filesystem on Every Send

## Intent
Every call to `Mailbox.send_message/4` results in the message being written atomically to both the `:observatory_mailboxes` ETS table and a JSON file in `~/.claude/inbox/{session_id}/{id}.json`. This ensures agents polling via the MCP `check_inbox` tool and LiveViews listening via PubSub both receive the message through their respective channels.

## Primary Actor
`Observatory.Mailbox` GenServer

## Supporting Actors
- ETS table `:observatory_mailboxes`
- `Observatory.CommandQueue` GenServer
- `Phoenix.PubSub` (`Observatory.PubSub`)

## Preconditions
- `Observatory.Mailbox` and `Observatory.CommandQueue` GenServers are both running and supervised.
- The `~/.claude/inbox/` base directory exists (created by `CommandQueue.init/1` per FR-3.10).

## Trigger
A caller invokes `Observatory.Mailbox.send_message(to, from, content, opts)`.

## Main Success Flow
1. The Mailbox GenServer constructs the message map (as specified in FR-3.2).
2. The GenServer inserts the message into the ETS table (newest-first prepend).
3. The GenServer calls `Observatory.CommandQueue.write_command(to, message_params)`, which creates the directory `~/.claude/inbox/{to}/` if absent and writes a JSON file at `~/.claude/inbox/{to}/{id}.json` containing the fields `type`, `from`, `content`, `message_type`, `metadata`, `id`, `session_id`, and `timestamp` (ISO 8601).
4. The GenServer broadcasts `{:new_mailbox_message, message}` on PubSub topic `"agent:#{to}"`.
5. The GenServer returns `{:ok, message}` to the caller.

## Alternate Flows

### A1: Session inbox directory does not yet exist
Condition: `~/.claude/inbox/{to}/` has not been created for this recipient before.
Steps:
1. `CommandQueue.write_command/2` calls `File.mkdir_p!("~/.claude/inbox/#{to}")` before writing.
2. The directory is created and the JSON file is written successfully.
3. All subsequent writes for this session reuse the existing directory.

## Failure Flows

### F1: CommandQueue write fails silently due to filesystem error
Condition: A filesystem permission error prevents `File.write!/2` from succeeding inside `CommandQueue.write_command/2`.
Steps:
1. The ETS insert has already completed successfully.
2. `CommandQueue.write_command/2` raises or returns an error.
3. PubSub is still broadcast (if PubSub occurs after ETS but before catching the CommandQueue error).
4. The message exists in ETS and the dashboard sees it, but no `~/.claude/inbox/{to}/{id}.json` file is created.
5. An agent polling via MCP `check_inbox` finds no file for this message.
Result: Partial delivery — ETS and PubSub channels have the message; MCP filesystem channel does not. After Phoenix restart, ETS is cleared and the message is permanently lost.

### F2: ETS write fails
Condition: The ETS table is unavailable (e.g., Mailbox GenServer restarting).
Steps:
1. `Mailbox.send_message/4` raises an error before reaching `CommandQueue.write_command/2`.
2. No ETS entry, no CommandQueue file, no PubSub event.
Result: Total message loss for this delivery attempt; caller receives an error.

## Gherkin Scenarios

### S1: Both ETS and filesystem contain message after send
```gherkin
Scenario: send_message writes to ETS and creates inbox JSON file
  Given Observatory.Mailbox and Observatory.CommandQueue are running
  And ~/.claude/inbox/ exists
  When Observatory.Mailbox.send_message("abc", "dashboard", "go", []) is called
  Then :ets.lookup(:observatory_mailboxes, "abc") returns a list containing the message
  And a file exists at ~/.claude/inbox/abc/{message.id}.json
  And the JSON file contains fields: type, from, content, message_type, metadata, id, session_id, timestamp
  And the timestamp field in the JSON file is an ISO 8601 string
```

### S2: MCP check_inbox finds the file
```gherkin
Scenario: Agent polling via MCP check_inbox finds the written file
  Given Observatory.Mailbox.send_message("abc", "dashboard", "go", []) was called
  And the file ~/.claude/inbox/abc/{id}.json was created
  When an agent calls the MCP check_inbox tool with session_id "abc"
  Then the tool returns the message content
```

### S3: Filesystem error leaves ETS populated but MCP channel empty
```gherkin
Scenario: Filesystem write failure causes partial delivery
  Given CommandQueue.write_command/2 raises a filesystem error for session "abc"
  When Observatory.Mailbox.send_message("abc", "dashboard", "go", []) is called
  Then :ets.lookup(:observatory_mailboxes, "abc") contains the message
  And no file exists at ~/.claude/inbox/abc/ for this message
```

## Acceptance Criteria
- [ ] `mix test` passes a test that calls `Mailbox.send_message("abc", "dashboard", "go", [])` and asserts both `:ets.lookup(:observatory_mailboxes, "abc")` and `File.ls!(Path.expand("~/.claude/inbox/abc/"))` return results containing the message (S1).
- [ ] The same test asserts the JSON file at `~/.claude/inbox/abc/{id}.json` parses successfully and contains all required fields including an ISO 8601 `timestamp` string (S1).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `to` (string), `from` (string), `content` (string), `opts` keyword list.
**Outputs:** `{:ok, message}`; ETS entry updated; JSON file written; PubSub broadcast emitted.
**State changes:** ETS `:observatory_mailboxes` prepended; `~/.claude/inbox/{to}/{id}.json` created.

## Traceability
- Parent FR: [FR-3.3](../frds/FRD-003-messaging-pipeline.md)
- ADR: [ADR-004](../../decisions/ADR-004-messaging-architecture.md)
- ADR: [ADR-005](../../decisions/ADR-005-ets-over-database.md)
