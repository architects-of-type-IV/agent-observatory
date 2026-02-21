---
id: UC-0056
title: Subscribe to Per-Session Mailbox Topics at Mount
status: draft
parent_fr: FR-3.7
adrs: [ADR-004]
---

# UC-0056: Subscribe to Per-Session Mailbox Topics at Mount

## Intent
During `mount/3`, `DashboardLive` subscribes to the `"agent:{session_id}"` PubSub topic for every active agent session derived from the event feed, not only the `"agent:dashboard"` topic. This ensures the dashboard receives real-time `{:new_mailbox_message, _}` events for messages addressed to or from any active agent session, enabling full cross-session message visibility.

## Primary Actor
`ObservatoryWeb.DashboardLive`

## Supporting Actors
- `Observatory.Channels` (`subscribe_agent/1`)
- `Phoenix.PubSub` (`Observatory.PubSub`)
- Event feed (source of active session IDs)

## Preconditions
- The LiveView connection is established (`connected?(socket)` returns `true`).
- At least one agent session ID is present in the event feed derived at mount time.
- `Observatory.Channels.subscribe_agent/1` calls `Phoenix.PubSub.subscribe/2` for the given session.

## Trigger
`DashboardLive.mount/3` is called with a connected socket, after the `"agent:dashboard"` subscription (FR-3.6) is registered.

## Main Success Flow
1. `mount/3` derives the list of active session IDs from the event feed (e.g., `["abc123", "xyz789"]`).
2. `mount/3` calls `subscribe_to_mailboxes(sessions)`.
3. `subscribe_to_mailboxes/1` iterates over each session ID and calls `Observatory.Channels.subscribe_agent(session_id)`.
4. `subscribe_agent/1` calls `Phoenix.PubSub.subscribe(Observatory.PubSub, "agent:#{session_id}")` for each session.
5. The dashboard process is now subscribed to `"agent:abc123"` and `"agent:xyz789"` in addition to `"agent:dashboard"`.
6. When the dashboard sends a message to `"abc123"` and `"abc123"` replies, the reply PubSub event on `"agent:abc123"` reaches the dashboard process.
7. `DashboardLive.handle_info({:new_mailbox_message, message}, socket)` fires and refreshes mailbox state.

## Alternate Flows

### A1: No active sessions at mount time
Condition: The event feed contains no session IDs at the time of mount.
Steps:
1. `subscribe_to_mailboxes([])` is called with an empty list.
2. No per-session subscriptions are registered beyond `"agent:dashboard"`.
3. The dashboard only receives messages addressed directly to `"dashboard"`.

## Failure Flows

### F1: Per-session subscriptions not registered
Condition: `subscribe_to_mailboxes/1` is not called or is called with an empty list despite active sessions.
Steps:
1. The dashboard sends a message to `"abc123"` and expects a reply.
2. The agent's reply is broadcast on `"agent:abc123"`.
3. The dashboard process has no subscription to `"agent:abc123"`.
4. The `handle_info` clause is not triggered.
Result: Messages addressed to non-dashboard session topics go unnoticed until the next full page load.

## Gherkin Scenarios

### S1: Per-session subscriptions registered at mount
```gherkin
Scenario: DashboardLive subscribes to all active agent session topics at mount
  Given two active sessions "abc123" and "xyz789" are present in the event feed
  When DashboardLive mounts with a connected socket
  Then the process is subscribed to "agent:abc123"
  And the process is subscribed to "agent:xyz789"
```

### S2: Cross-session reply triggers real-time update
```gherkin
Scenario: Agent reply on session topic updates dashboard in real time
  Given DashboardLive is mounted and subscribed to "agent:abc123"
  When Observatory.Mailbox.send_message("abc123", "dashboard", "reply here", []) is called
  Then DashboardLive receives {:new_mailbox_message, message} on "agent:abc123"
  And refresh_mailbox_assigns/1 is called
  And the dashboard updates without a page reload
```

### S3: No sessions at mount means no per-session subscriptions
```gherkin
Scenario: Empty event feed results in no per-session subscriptions
  Given the event feed contains no session IDs at mount time
  When DashboardLive mounts
  Then no per-session "agent:{id}" subscriptions beyond "agent:dashboard" are registered
```

## Acceptance Criteria
- [ ] `mix test` passes a LiveView test that seeds two session IDs into the event feed before mounting, then asserts via `Phoenix.PubSub.broadcast/3` and `assert_receive` that the mounted process receives events on both `"agent:abc123"` and `"agent:xyz789"` (S1).
- [ ] A test asserts that `Mailbox.send_message("abc123", "other-agent", "reply", [])` triggers a LiveView re-render when the dashboard is subscribed to `"agent:abc123"` (S2).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** List of active session IDs from the event feed.
**Outputs:** PubSub subscriptions registered for each session ID.
**State changes:** Dashboard process receives future `{:new_mailbox_message, _}` events for all subscribed session topics.

## Traceability
- Parent FR: [FR-3.7](../frds/FRD-003-messaging-pipeline.md)
- ADR: [ADR-004](../../decisions/ADR-004-messaging-architecture.md)
