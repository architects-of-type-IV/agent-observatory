---
id: UC-0050
title: Route Outbound Dashboard Message Through Mailbox Single Entry Point
status: draft
parent_fr: FR-3.1
adrs: [ADR-004, ADR-005]
---

# UC-0050: Route Outbound Dashboard Message Through Mailbox Single Entry Point

## Intent
Every outbound message originating from any of the four dashboard forms is routed exclusively through `Observatory.Mailbox.send_message/4`. No form event handler may bypass the Mailbox by calling `CommandQueue.write_command/2` or `Phoenix.PubSub.broadcast/3` directly, ensuring all three delivery channels (ETS, filesystem, PubSub) are written atomically on every send.

## Primary Actor
Dashboard Operator

## Supporting Actors
- `Observatory.Mailbox` GenServer
- `ObservatoryWeb.DashboardLive` event handlers

## Preconditions
- The Phoenix application is running with `Observatory.Mailbox` and `Observatory.CommandQueue` GenServers supervised and started.
- The operator has the dashboard loaded in a browser session.

## Trigger
The operator submits one of the four dashboard message forms: `send_targeted_message`, `send_agent_message`, `send_team_broadcast`, or `send_command_message`.

## Main Success Flow
1. The operator fills in the message form and submits it.
2. The `DashboardLive` event handler for the submitted form receives the `phx-submit` event.
3. The handler calls `Observatory.Mailbox.send_message/4` (or `Observatory.Mailbox.broadcast_to_many/4` for the team broadcast form) with the appropriate `to`, `from`, `content`, and `opts` arguments.
4. `Mailbox.send_message/4` performs the atomic triple write: ETS insert, CommandQueue file write, PubSub broadcast.
5. `Mailbox.send_message/4` returns `{:ok, message}`.
6. The event handler updates the LiveView socket state and the form clears via the `ClearFormOnSubmit` JS hook.

## Alternate Flows

### A1: Team broadcast uses broadcast_to_many
Condition: The submitted form is `send_team_broadcast`.
Steps:
1. The handler calls `Mailbox.broadcast_to_many/4` with the list of team member session IDs.
2. `broadcast_to_many/4` calls `send_message/4` once per recipient.
3. Each recipient receives an independent ETS entry, CommandQueue file, and PubSub event.

## Failure Flows

### F1: Handler bypasses Mailbox and calls CommandQueue directly
Condition: A developer modifies a handler to call `CommandQueue.write_command/2` directly instead of `Mailbox.send_message/4`.
Steps:
1. The CommandQueue file is written but ETS is not updated.
2. `unread_count/1` returns 0 for the recipient regardless of actual pending messages.
3. PubSub is not broadcast; the dashboard does not refresh in real time.
Result: Partial delivery — the agent may receive the message via MCP polling but the dashboard shows no confirmation and loses real-time state sync.

### F2: Handler bypasses Mailbox and calls PubSub directly
Condition: A developer modifies a handler to call `Phoenix.PubSub.broadcast/3` directly.
Steps:
1. PubSub fires but ETS is not updated and no CommandQueue file is written.
2. The dashboard briefly shows the message (if subscribed) but it vanishes on the next render cycle.
3. The agent's MCP `check_inbox` finds no file; the message is never delivered to the agent.
Result: Message appears delivered on the dashboard but is silently dropped from agent delivery.

## Gherkin Scenarios

### S1: Targeted message routed through Mailbox
```gherkin
Scenario: Operator sends targeted message via send_targeted_message form
  Given the Observatory dashboard is mounted and connected
  And the Observatory.Mailbox GenServer is running
  When the operator submits the send_targeted_message form with recipient "agent-42" and content "hello"
  Then DashboardLive calls Observatory.Mailbox.send_message/4 with to: "agent-42"
  And Mailbox.send_message/4 returns {:ok, message}
  And the ETS table :observatory_mailboxes contains the message for "agent-42"
  And a JSON file exists at ~/.claude/inbox/agent-42/{id}.json
  And a PubSub event {:new_mailbox_message, message} is broadcast on "agent:agent-42"
```

### S2: Team broadcast routed through broadcast_to_many
```gherkin
Scenario: Operator broadcasts to team via send_team_broadcast form
  Given three team member session IDs ["a", "b", "c"] are known to DashboardLive
  When the operator submits the send_team_broadcast form
  Then DashboardLive calls Observatory.Mailbox.broadcast_to_many/4 with ["a", "b", "c"]
  And send_message/4 is called exactly once per recipient
  And each of "a", "b", "c" has an ETS entry and a CommandQueue file
```

### S3: Direct CommandQueue call bypasses ETS
```gherkin
Scenario: Bypassing Mailbox leaves ETS out of sync
  Given an event handler calls CommandQueue.write_command/2 directly instead of Mailbox.send_message/4
  When the message is written
  Then the ETS table :observatory_mailboxes does NOT contain the message
  And Mailbox.unread_count("agent-42") returns 0
  And no PubSub event is broadcast on "agent:agent-42"
```

## Acceptance Criteria
- [ ] All four `DashboardLive` form event handlers call `Mailbox.send_message/4` or `Mailbox.broadcast_to_many/4` as their sole delivery mechanism; no handler calls `CommandQueue.write_command/2` or `Phoenix.PubSub.broadcast/3` directly (verified by `grep -r "CommandQueue.write_command\|PubSub.broadcast" lib/observatory_web/` returning no results in handler modules).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Form fields — `to` (session ID string), `content` (string), optional `type` atom and `metadata` map.
**Outputs:** `{:ok, message}` from `Mailbox.send_message/4`; LiveView socket updated; form cleared.
**State changes:** ETS entry inserted; CommandQueue JSON file created; PubSub broadcast emitted.

## Traceability
- Parent FR: [FR-3.1](../frds/FRD-003-messaging-pipeline.md)
- ADR: [ADR-004](../../decisions/ADR-004-messaging-architecture.md)
