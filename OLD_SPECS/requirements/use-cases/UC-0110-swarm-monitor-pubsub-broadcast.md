---
id: UC-0110
title: Broadcast SwarmMonitor state to dashboard via PubSub
status: draft
parent_fr: FR-4.11
adrs: [ADR-007]
---

# UC-0110: Broadcast SwarmMonitor State to Dashboard via PubSub

## Intent
After every poll cycle, health check, and mutation action, SwarmMonitor broadcasts its complete state to the `"swarm:update"` PubSub topic. The dashboard LiveView subscribes on mount and applies each broadcast to keep the swarm view current without polling.

## Primary Actor
`Observatory.SwarmMonitor`

## Supporting Actors
- `Phoenix.PubSub` with name `Observatory.PubSub`
- `ObservatoryWeb.DashboardLive` (subscriber)

## Preconditions
- `Phoenix.PubSub` is started in the supervision tree before `SwarmMonitor`.
- `DashboardLive` has called `Phoenix.PubSub.subscribe(Observatory.PubSub, "swarm:update")` in `mount/3`.

## Trigger
SwarmMonitor completes any of: a task poll cycle, a health check, or a mutation action.

## Main Success Flow
1. SwarmMonitor calls `Phoenix.PubSub.broadcast(Observatory.PubSub, "swarm:update", {:swarm_state, state})`.
2. All subscribed `DashboardLive` processes receive `{:swarm_state, state}` in their mailbox.
3. `handle_info({:swarm_state, state}, socket)` runs in each subscriber.
4. The socket's `:swarm_state` assign is updated: `assign(socket, :swarm_state, state)`.
5. The dashboard re-renders the swarm view with current data.

## Alternate Flows

### A1: Multiple dashboard sessions subscribed simultaneously
Condition: Two browser tabs have `DashboardLive` mounted and both are subscribed.
Steps:
1. The single broadcast reaches both processes.
2. Each session independently applies `assign/3` and re-renders.

### A2: Dashboard not yet subscribed at first broadcast
Condition: The dashboard LiveView is not yet mounted when the first poll fires.
Steps:
1. The broadcast is delivered to zero subscribers.
2. When the dashboard mounts later, it calls `SwarmMonitor.get_state()` directly for the initial assign.
3. Subsequent broadcasts are received normally.

## Failure Flows

### F1: PubSub not started before SwarmMonitor
Condition: Application supervision order places `SwarmMonitor` before `Phoenix.PubSub`.
Steps:
1. `Phoenix.PubSub.broadcast/3` raises because the named PubSub process does not exist.
2. SwarmMonitor crashes on the first broadcast.
3. The supervisor restarts SwarmMonitor; if PubSub is started by then, the restart succeeds.
Result: Application may fail to start if the supervision order is wrong. The order MUST be corrected.

## Gherkin Scenarios

### S1: Dashboard receives state update after task poll
```gherkin
Scenario: Dashboard LiveView receives broadcast after each task poll cycle
  Given DashboardLive is mounted and subscribed to "swarm:update"
  When SwarmMonitor completes a :poll_tasks cycle
  Then DashboardLive receives a {:swarm_state, state} message
  And socket.assigns.swarm_state is updated to the new state
```

### S2: Dashboard uses get_state for initial mount assign
```gherkin
Scenario: Dashboard fetches initial state synchronously on mount
  Given SwarmMonitor is running with current state
  When DashboardLive mounts
  Then it calls SwarmMonitor.get_state() to populate the initial :swarm_state assign
  And subsequent state changes arrive via PubSub broadcasts
```

### S3: No broadcast when active_project is nil and no change
```gherkin
Scenario: Broadcast only fires when state actually changes
  Given state.active_project is nil and no tasks have changed
  When :poll_tasks fires and discovers no new projects
  Then a broadcast may or may not fire (implementation may optimise)
  And DashboardLive does not crash if a broadcast does arrive
```

## Acceptance Criteria
- [ ] A LiveView test that subscribes to `"swarm:update"` and triggers a manual `send(SwarmMonitor, :poll_tasks)` asserts `assert_receive {:swarm_state, _}` within 1 second (S1).
- [ ] `DashboardLive` mount assigns `:swarm_state` from `SwarmMonitor.get_state()` without error when the dashboard first loads (S2).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Complete SwarmMonitor state map
**Outputs:** `{:swarm_state, state}` PubSub message delivered to all subscribers
**State changes:** No state changes in SwarmMonitor; subscriber socket assigns updated

## Traceability
- Parent FR: [FR-4.11](../frds/FRD-004-swarm-monitor-protocol-tracker.md)
- ADR: [ADR-007](../../decisions/ADR-007-swarm-monitor-design.md)
