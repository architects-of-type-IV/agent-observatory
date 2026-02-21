---
id: UC-0143
title: Execute prepare_assigns unconditionally on every state change
status: draft
parent_fr: FR-5.19
adrs: [ADR-012]
---

# UC-0143: Execute prepare_assigns Unconditionally on Every State Change

## Intent
`prepare_assigns/1` must be called unconditionally -- never with an `if`, `case`, or flag guard -- because every call recomputes all derived assigns including time-sensitive data like member status. Conditional execution produces stale view data that does not self-correct until the next unconditional call.

## Primary Actor
`ObservatoryWeb.DashboardLive`

## Supporting Actors
- `prepare_assigns/1` function
- `:tick` timer (fires every 1 second)
- All `Dashboard*Handlers` modules

## Preconditions
- `DashboardLive` is running and mounted.
- A callback (event, info, or mount) is executing.

## Trigger
Any `handle_event/3`, `handle_info/2`, or `mount/3` invocation.

## Main Success Flow
1. Any callback executes and modifies (or does not modify) socket state.
2. `prepare_assigns/1` is called unconditionally on the resulting socket.
3. All derived assigns are recomputed: sessions, teams with enriched members, feed groups, filtered events, errors, analytics, timeline data.
4. The updated socket is returned to the LiveView runtime.
5. The view renders with fully current data.

## Alternate Flows

### A1: :tick fires without any user-initiated event
Condition: The 1-second `:tick` timer fires with no user activity.
Steps:
1. `handle_info(:tick, socket)` updates `:now` to `DateTime.utc_now()`.
2. `prepare_assigns/1` is called.
3. Member statuses are recomputed using the new `:now` value.
4. An agent that went silent 31 seconds ago transitions from `:active` to `:idle`.

## Failure Flows

### F1: prepare_assigns called conditionally on :tick
Condition: Developer adds `if events_changed?, do: prepare_assigns(socket), else: socket` to the `:tick` handler.
Steps:
1. On ticks where no new events arrive, `prepare_assigns/1` is skipped.
2. `:now` is updated but member status computation uses the stale previous `:now`.
3. A member that went silent remains `:active` past the 30-second threshold.
4. The dashboard shows incorrect member activity.
Result: Stale status; fix by removing the conditional and always calling `prepare_assigns/1`.

## Gherkin Scenarios

### S1: :tick always calls prepare_assigns regardless of event changes
```gherkin
Scenario: :tick handler calls prepare_assigns even when no new events arrived
  Given DashboardLive is running and no new events have arrived in 5 seconds
  When a :tick message fires
  Then handle_info(:tick, socket) calls prepare_assigns unconditionally
  And socket.assigns.now is updated
  And member statuses are recomputed based on the new now value
```

### S2: Member status transitions on tick without user action
```gherkin
Scenario: Member transitions from :active to :idle on a :tick when no recent events
  Given a team member had their last event 31 seconds ago
  And their current :status is :active
  When a :tick fires and prepare_assigns recomputes member statuses
  Then the member's :status becomes :idle
  And the dashboard reflects the :idle status without user interaction
```

### S3: mount/3 calls prepare_assigns before first render
```gherkin
Scenario: mount/3 always calls prepare_assigns as its final step
  Given DashboardLive is mounting with initial raw assigns
  When mount/3 completes
  Then {:ok, prepare_assigns(socket)} is returned
  And the first render has all derived assigns populated
```

## Acceptance Criteria
- [ ] `grep -n "if.*prepare_assigns\|unless.*prepare_assigns\|prepare_assigns.*if" lib/observatory_web/live/dashboard_live.ex` returns no matches (no conditional calls to `prepare_assigns`) (S1).
- [ ] A LiveView test with a team member whose last event was 31 seconds ago asserts `:status == :idle` after receiving a `:tick` message (S2).
- [ ] `grep -n "prepare_assigns" lib/observatory_web/live/dashboard_live.ex` shows at least one call in `mount/3` (S3).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Socket state at the time of the callback; current `DateTime.utc_now()` for time-sensitive computations
**Outputs:** Socket with all derived assigns recomputed unconditionally
**State changes:** All derived assigns updated on every callback invocation

## Traceability
- Parent FR: [FR-5.19](../frds/FRD-005-code-architecture-patterns.md)
- ADR: [ADR-012](../../decisions/ADR-012-dual-data-sources.md)
