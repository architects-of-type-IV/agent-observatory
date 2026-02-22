---
id: UC-0115
title: Compute and broadcast protocol stats every 5 seconds
status: draft
parent_fr: FR-4.16
adrs: [ADR-007]
---

# UC-0115: Compute and Broadcast Protocol Stats Every 5 Seconds

## Intent
Every 5 seconds, ProtocolTracker computes a `stats` map aggregating trace counts, Mailbox state, and CommandQueue state, then broadcasts it on `"protocols:update"`. The dashboard LiveView subscribes and uses these stats to render the Protocols tab without polling.

## Primary Actor
`Observatory.ProtocolTracker`

## Supporting Actors
- `Observatory.Mailbox` (provides `get_stats/0`)
- `Observatory.CommandQueue` (provides `get_queue_stats/0`)
- `Phoenix.PubSub` (broadcast on `"protocols:update"`)
- `ObservatoryWeb.DashboardLive` (subscriber)

## Preconditions
- ProtocolTracker is running.
- `Observatory.Mailbox` and `Observatory.CommandQueue` are started in the supervision tree before `ProtocolTracker`.
- `DashboardLive` has subscribed to `"protocols:update"` in `mount/3`.

## Trigger
`handle_info(:compute_stats, state)` fires on the 5-second interval.

## Main Success Flow
1. ProtocolTracker reads all traces from `:protocol_traces` via `get_traces/0`.
2. `traces` count is computed as the length of the trace list.
3. `by_type` is built as a frequency map: `%{send_message: N, team_create: N, agent_spawn: N}`.
4. `mailbox` is computed from `Observatory.Mailbox.get_stats()`: `%{agents: count, total_pending: sum}`.
5. `command_queue` is computed from `Observatory.CommandQueue.get_queue_stats()`: `%{sessions: count, total_pending: sum}`.
6. `mailbox_detail` and `queue_detail` hold the raw lists from the above calls.
7. The `stats` map is broadcast on `"protocols:update"` as `{:protocol_update, stats}`.
8. The next `:compute_stats` message is scheduled 5 seconds later.

## Alternate Flows

### A1: No traces in ETS
Condition: `:protocol_traces` is empty.
Steps:
1. `traces` is 0.
2. `by_type` is `%{}` (empty map).
3. Other stats fields are computed normally from Mailbox and CommandQueue.

## Failure Flows

### F1: Mailbox or CommandQueue not yet started
Condition: `Observatory.Mailbox.get_stats()` raises because Mailbox is not started.
Steps:
1. The call returns an empty list rather than crashing, because Mailbox is started before ProtocolTracker in the supervision tree.
2. `mailbox` is `%{agents: 0, total_pending: 0}`.
Result: Stats broadcast proceeds without error; Mailbox absence is represented as zeros.

## Gherkin Scenarios

### S1: Stats broadcast contains trace counts and mailbox data
```gherkin
Scenario: Protocol stats broadcast includes all required fields
  Given :protocol_traces has 3 traces: 2 of type :send_message and 1 of type :agent_spawn
  And Observatory.Mailbox.get_stats() returns data for 2 agents
  When :compute_stats fires
  Then a {:protocol_update, stats} message is broadcast on "protocols:update"
  And stats.traces is 3
  And stats.by_type.send_message is 2
  And stats.by_type.agent_spawn is 1
  And stats.mailbox.agents is 2
```

### S2: Dashboard receives stats update and updates :protocol_stats assign
```gherkin
Scenario: DashboardLive receives protocol stats and updates the assign
  Given DashboardLive is mounted and subscribed to "protocols:update"
  When ProtocolTracker broadcasts {:protocol_update, stats}
  Then handle_info({:protocol_update, stats}, socket) runs in DashboardLive
  And socket.assigns.protocol_stats is set to the new stats map
```

### S3: Empty ETS table produces zero-count stats
```gherkin
Scenario: Stats with no traces has traces count of zero
  Given :protocol_traces is empty
  When :compute_stats fires
  Then stats.traces is 0
  And stats.by_type is an empty map or has all zero values
```

## Acceptance Criteria
- [ ] A LiveView test subscribed to `"protocols:update"` asserts `assert_receive {:protocol_update, %{traces: _, by_type: _, mailbox: _, command_queue: _}}` within 6 seconds of ProtocolTracker starting (S1).
- [ ] `socket.assigns.protocol_stats` is non-nil after the first broadcast arrives in `DashboardLive` (S2).
- [ ] With no traces in ETS, the broadcast stats map has `traces: 0` (S3).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `:protocol_traces` ETS table; `Mailbox.get_stats()` return; `CommandQueue.get_queue_stats()` return
**Outputs:** `{:protocol_update, stats}` PubSub broadcast on `"protocols:update"`
**State changes:** No state changes in ProtocolTracker; dashboard `:protocol_stats` assign updated

## Traceability
- Parent FR: [FR-4.16](../frds/FRD-004-swarm-monitor-protocol-tracker.md)
- ADR: [ADR-007](../../decisions/ADR-007-swarm-monitor-design.md)
