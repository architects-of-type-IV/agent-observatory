---
id: UC-0055
title: Dashboard Subscribes to Agent Inbox Topic at Mount
status: draft
parent_fr: FR-3.6
adrs: [ADR-004]
---

# UC-0055: Dashboard Subscribes to Agent Inbox Topic at Mount

## Intent
When `ObservatoryWeb.DashboardLive` mounts in a connected socket, it subscribes to the `"agent:dashboard"` PubSub topic and assigns `current_session_id: "dashboard"` to the socket. This ensures that agent-to-dashboard messages routed through `Mailbox.send_message("dashboard", ...)` trigger a real-time UI refresh via `handle_info({:new_mailbox_message, message}, socket)`.

## Primary Actor
`ObservatoryWeb.DashboardLive`

## Supporting Actors
- `Phoenix.PubSub` (`Observatory.PubSub`)
- `Observatory.Mailbox` (source of PubSub events)

## Preconditions
- The LiveView connection is established (`connected?(socket)` returns `true`).
- The `Observatory.PubSub` supervisor is running.

## Trigger
`DashboardLive.mount/3` is called with a connected socket.

## Main Success Flow
1. `mount/3` checks `connected?(socket)` — it is `true`.
2. `mount/3` calls `Phoenix.PubSub.subscribe(Observatory.PubSub, "agent:dashboard")`.
3. `mount/3` assigns `current_session_id: "dashboard"` to the socket.
4. The dashboard is now capable of receiving real-time `{:new_mailbox_message, _}` events.
5. When an agent calls MCP `send_message` targeting `"dashboard"`, `Mailbox.send_message("dashboard", agent_sid, content)` fires, which broadcasts on `"agent:dashboard"`.
6. `DashboardLive.handle_info({:new_mailbox_message, message}, socket)` is invoked.
7. `handle_new_mailbox_message/2` calls `refresh_mailbox_assigns/1`, recomputing unread counts.
8. The LiveView re-renders; the operator sees the updated message count immediately.

## Alternate Flows

### A1: Mount during static render (not yet connected)
Condition: `connected?(socket)` returns `false` during the initial static render phase.
Steps:
1. The subscription and `current_session_id` assignment are skipped in this render.
2. On the subsequent connected mount, `mount/3` runs again and performs the subscription.

## Failure Flows

### F1: Dashboard does not subscribe to "agent:dashboard"
Condition: The `Phoenix.PubSub.subscribe` call is absent from `mount/3`.
Steps:
1. `Mailbox.send_message("dashboard", agent_sid, content)` broadcasts on `"agent:dashboard"`.
2. The dashboard process has no subscription; the event is not delivered.
3. `DashboardLive.handle_info` is never called.
4. Messages accumulate in ETS without any visible indicator to the operator.
Result: Silent message delivery failure — the exact bug documented in ADR-004 before the fix.

### F2: current_session_id not assigned
Condition: The socket is missing the `current_session_id: "dashboard"` assign.
Steps:
1. Outbound messages from the dashboard use a nil or undefined `from` field.
2. Agents receive messages where `from` is nil, breaking message attribution.
3. The MCP `send_message` tool cannot attribute replies correctly.
Result: Broken message attribution; agents cannot address replies back to `"dashboard"`.

## Gherkin Scenarios

### S1: Dashboard subscribes at connected mount
```gherkin
Scenario: DashboardLive subscribes to "agent:dashboard" on connected mount
  Given a Phoenix LiveView test with a connected DashboardLive mount
  When the LiveView process mounts
  Then the process is subscribed to "agent:dashboard" PubSub topic
  And socket assigns include current_session_id: "dashboard"
```

### S2: Agent reply triggers real-time dashboard update
```gherkin
Scenario: Agent message to dashboard updates unread count in real time
  Given DashboardLive is mounted and subscribed to "agent:dashboard"
  When Observatory.Mailbox.send_message("dashboard", "agent-42", "task complete", []) is called
  Then DashboardLive receives {:new_mailbox_message, message} via handle_info
  And refresh_mailbox_assigns/1 is called
  And the dashboard unread count is updated without a page reload
```

### S3: Missing subscription prevents real-time update
```gherkin
Scenario: Absent subscription leaves dashboard unrefreshed after agent message
  Given DashboardLive is mounted without subscribing to "agent:dashboard"
  When Observatory.Mailbox.send_message("dashboard", "agent-42", "done", []) is called
  Then DashboardLive.handle_info is NOT invoked for this message
  And the dashboard unread count does not change
```

## Acceptance Criteria
- [ ] `mix test` passes a LiveView test using `Phoenix.LiveViewTest.live/2` that asserts the mounted LiveView process is subscribed to `"agent:dashboard"` (verified by sending a PubSub message and asserting `render/1` changes) (S1).
- [ ] The same test asserts `socket.assigns.current_session_id == "dashboard"` (S1).
- [ ] A test sends `Mailbox.send_message("dashboard", "agent-42", "hi", [])` and asserts the LiveView re-renders with updated mailbox state using `assert render(view) =~ "unread"` or equivalent (S2).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Connected socket from LiveView mount lifecycle.
**Outputs:** PubSub subscription registered; socket assign `current_session_id: "dashboard"` set.
**State changes:** Process receives future `{:new_mailbox_message, _}` events on `"agent:dashboard"`.

## Traceability
- Parent FR: [FR-3.6](../frds/FRD-003-messaging-pipeline.md)
- ADR: [ADR-004](../../decisions/ADR-004-messaging-architecture.md)
