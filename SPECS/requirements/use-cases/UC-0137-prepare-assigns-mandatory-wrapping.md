---
id: UC-0137
title: Wrap every state-modifying callback with prepare_assigns
status: draft
parent_fr: FR-5.13
adrs: [ADR-011]
---

# UC-0137: Wrap Every State-Modifying Callback with prepare_assigns

## Intent
`prepare_assigns/1` is the single recomputation point for all derived assigns (sessions, teams, feed groups, filtered events, analytics, timeline). It must be called on the resulting socket in every `handle_event/3` and `handle_info/2` clause that modifies socket state, and also at the end of `mount/3`. Skipping it for any clause produces stale derived data in the view.

## Primary Actor
`ObservatoryWeb.DashboardLive`

## Supporting Actors
- `prepare_assigns/1` function
- All `Dashboard*Handlers` modules
- Dashboard templates (consume derived assigns)

## Preconditions
- `DashboardLive` is running and has mounted successfully.
- A `handle_event/3` or `handle_info/2` clause is about to return.

## Trigger
Any event or info message arrives that modifies socket state.

## Main Success Flow
1. `handle_event("set_view", %{"mode" => m}, s)` delegates to `handle_set_view(m, s)`.
2. The handler returns a socket with `:view_mode` updated.
3. `DashboardLive` applies `prepare_assigns/1`: `{:noreply, handle_set_view(m, s) |> prepare_assigns()}`.
4. `prepare_assigns/1` recomputes `:sessions`, `:teams`, `:feed_groups`, `:filtered_events`, `:errors`, and all other derived assigns.
5. The view renders with current data.

## Alternate Flows

### A1: mount/3 calls prepare_assigns at the end
Condition: `mount/3` finishes setting initial assigns.
Steps:
1. `mount/3` sets raw assigns (events, teams, view_mode, etc.).
2. `prepare_assigns/1` is called as the last step: `{:ok, prepare_assigns(socket)}`.
3. All derived assigns are computed before the first render.

## Failure Flows

### F1: prepare_assigns skipped in handle_info(:tick, socket)
Condition: The `:tick` handler updates `:now` but returns without calling `prepare_assigns/1`.
Steps:
1. `:now` is updated in the socket.
2. Member statuses (which compare event timestamps against `:now`) are not recomputed.
3. A member that stopped emitting events 35 seconds ago remains `:active` because the comparison uses the stale `:now`.
4. The sidebar shows incorrect member status.
Result: Stale view data; detected by comparing the UI against actual event timestamps.

## Gherkin Scenarios

### S1: prepare_assigns called in every handle_event clause
```gherkin
Scenario: Every handle_event clause calls prepare_assigns before returning
  Given the current DashboardLive source file
  When all handle_event clauses are inspected
  Then every clause that modifies socket assigns calls prepare_assigns before {:noreply, ...}
  And no clause returns {:noreply, socket} without prepare_assigns
```

### S2: :tick handler calls prepare_assigns to keep member status current
```gherkin
Scenario: :tick handler recomputes member statuses via prepare_assigns
  Given DashboardLive receives a :tick message
  And a team member stopped emitting events 35 seconds ago
  When handle_info(:tick, socket) calls prepare_assigns
  Then the member's :status is recomputed as :idle (> 30 second threshold)
  And the dashboard reflects the :idle status
```

### S3: mount/3 calls prepare_assigns before first render
```gherkin
Scenario: mount/3 calls prepare_assigns as its final step
  Given DashboardLive is mounting
  When mount/3 sets initial assigns and calls prepare_assigns
  Then {:ok, socket} is returned with all derived assigns populated
  And the first render has current session, team, and feed data
```

## Acceptance Criteria
- [ ] `grep -c "prepare_assigns" lib/observatory_web/live/dashboard_live.ex` returns N where N equals the number of `handle_event` + `handle_info` + `mount` clauses (every clause uses it) (S1).
- [ ] `grep -n "{:noreply, socket}" lib/observatory_web/live/dashboard_live.ex` returns no matches (direct socket returns without prepare_assigns are prohibited) (S1).
- [ ] A LiveView integration test confirms that after a `:tick` message, the dashboard's `:teams` assign reflects updated member statuses (S2).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Socket after state modification by handler or callback
**Outputs:** Socket with all derived assigns recomputed
**State changes:** All derived assigns (`:sessions`, `:teams`, `:feed_groups`, `:filtered_events`, `:errors`, `:analytics`, `:timeline_data`) updated atomically

## Traceability
- Parent FR: [FR-5.13](../frds/FRD-005-code-architecture-patterns.md)
- ADR: [ADR-011](../../decisions/ADR-011-handler-delegation.md)
