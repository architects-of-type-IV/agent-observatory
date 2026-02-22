---
id: UC-0138
title: Route navigation events through a shared guard clause
status: draft
parent_fr: FR-5.14
adrs: [ADR-011]
---

# UC-0138: Route Navigation Events Through a Shared Guard Clause

## Intent
Navigation events that share a single handler module are routed via a guard clause in `DashboardLive` that matches a known set of event name strings. The guard clause appears after all specific `handle_event` clauses so that specific handlers take precedence. New navigation events are added to the guard's `when e in [...]` list rather than as standalone clauses.

## Primary Actor
`ObservatoryWeb.DashboardLive`

## Supporting Actors
- `ObservatoryWeb.DashboardNavigationHandlers`
- `prepare_assigns/1`

## Preconditions
- `DashboardNavigationHandlers` module exists and is imported.
- At least one navigation event name is in the guard list.

## Trigger
A user action triggers a navigation event (e.g., "jump_to_timeline", "jump_to_feed").

## Main Success Flow
1. A "jump_to_timeline" event is dispatched.
2. `DashboardLive` evaluates specific `handle_event` clauses first; none match.
3. The guard clause `def handle_event(e, p, s) when e in ["jump_to_timeline", "jump_to_feed", ...]` matches.
4. The clause delegates to `DashboardNavigationHandlers.handle_event(e, p, s)`.
5. The handler returns `socket`.
6. `prepare_assigns/1` is applied and `{:noreply, socket}` is returned.

## Alternate Flows

### A1: Adding a new navigation event
Condition: A "jump_to_errors" event is added to the navigation flow.
Steps:
1. `"jump_to_errors"` is added to the `when e in [...]` list in `DashboardLive`.
2. A handler clause for `"jump_to_errors"` is added to `DashboardNavigationHandlers`.
3. No new `handle_event` clause is added to `DashboardLive` itself.
4. `mix compile --warnings-as-errors` passes.

## Failure Flows

### F1: New navigation event added as standalone clause before guard
Condition: Developer adds `def handle_event("jump_to_errors", p, s)` as a standalone clause in `DashboardLive`.
Steps:
1. The standalone clause duplicates the guard pattern.
2. Code review identifies the redundancy.
3. The standalone clause is removed.
4. `"jump_to_errors"` is added to the guard list.
5. The handler is implemented inside `DashboardNavigationHandlers`.
6. `mix compile --warnings-as-errors` passes.
Result: Navigation routing consolidated in the guard and handler module.

## Gherkin Scenarios

### S1: Navigation event matched by guard clause and delegated
```gherkin
Scenario: jump_to_timeline event is handled via the navigation guard clause
  Given "jump_to_timeline" is in the when e in [...] guard list
  And DashboardNavigationHandlers.handle_event/3 handles it
  When a user triggers the jump_to_timeline event
  Then the guard clause matches and delegates to DashboardNavigationHandlers
  And prepare_assigns is called on the result
  And {:noreply, socket} is returned
```

### S2: New navigation event added to guard list not as standalone clause
```gherkin
Scenario: A new navigation event is added to the guard list not as a new clause
  Given DashboardLive has a navigation guard clause with 3 event names
  When a developer adds "jump_to_errors" to the navigation flow
  Then "jump_to_errors" is added to the when e in [...] list
  And DashboardNavigationHandlers.handle_event/3 gains a new clause for it
  And no standalone handle_event("jump_to_errors", ...) clause exists in DashboardLive
```

## Acceptance Criteria
- [ ] `grep -n "when e in" lib/observatory_web/live/dashboard_live.ex` shows exactly one guard clause for navigation events (S1).
- [ ] The guard clause appears after all other `handle_event` clauses in the file (S1).
- [ ] `grep -n '"jump_to' lib/observatory_web/live/dashboard_live.ex` shows only the guard clause and no standalone clauses for jump_ events (S2).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Navigation event name string; event params; current socket
**Outputs:** Updated socket via `DashboardNavigationHandlers`; `{:noreply, socket}` returned to LiveView runtime
**State changes:** `:view_mode`, `:selected_event`, or navigation-related assigns updated

## Traceability
- Parent FR: [FR-5.14](../frds/FRD-005-code-architecture-patterns.md)
- ADR: [ADR-011](../../decisions/ADR-011-handler-delegation.md)
