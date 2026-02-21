---
id: UC-0007
title: Toggle sidebar collapsed state and persist via StatePersistence hook
status: draft
parent_fr: FR-1.7
adrs: [ADR-001, ADR-003, ADR-008]
---

# UC-0007: Toggle Sidebar Collapsed State and Persist via StatePersistence Hook

## Intent
The operator can collapse or expand the dashboard sidebar using a toggle control. `DashboardLive` maintains a `:sidebar_collapsed` boolean assign. Each toggle inverts the current value and pushes a `"filters_changed"` event so the `StatePersistence` hook can write the new state to localStorage independently of view mode, enabling the sidebar preference to survive page reloads.

## Primary Actor
Operator

## Supporting Actors
- `ObservatoryWeb.DashboardLive` (`:sidebar_collapsed` assign)
- `ObservatoryWeb.DashboardUIHandlers.handle_event("toggle_sidebar", ...)`
- `StatePersistence` JS hook

## Preconditions
- The LiveView is mounted with `:sidebar_collapsed` initialized to `false`.
- The `StatePersistence` hook is attached to `id="view-mode-toggle"`.

## Trigger
The operator clicks the sidebar collapse control, pushing `handle_event("toggle_sidebar", %{}, socket)`.

## Main Success Flow
1. `handle_event("toggle_sidebar", %{}, socket)` reads `socket.assigns.sidebar_collapsed` (currently `false`).
2. The handler assigns `:sidebar_collapsed` to `true`.
3. The handler pushes `"filters_changed"` with `%{sidebar_collapsed: "true"}`.
4. The `StatePersistence` hook writes `"true"` to the sidebar_collapsed key in localStorage.
5. The sidebar CSS class `collapsed` is applied; the sidebar visually collapses.
6. On next page load, `restore_state` pushes `sidebar_collapsed: "true"`, and `maybe_restore/3` assigns `true` to `:sidebar_collapsed`.

## Alternate Flows

### A1: Expanding a collapsed sidebar
Condition: `:sidebar_collapsed` is currently `true`.
Steps:
1. `handle_event("toggle_sidebar", ...)` assigns `false`.
2. `push_event("filters_changed", %{sidebar_collapsed: "false"})` fires.
3. The `StatePersistence` hook writes `"false"` to localStorage.
4. The sidebar expands.

## Failure Flows

### F1: restore_state arrives with sidebar_collapsed "false"
Condition: `restore_state` delivers `%{"sidebar_collapsed" => "false"}`.
Steps:
1. `maybe_restore(socket, :sidebar_collapsed, "false")` hits the catch-all clause.
2. `:sidebar_collapsed` is left unchanged (effectively `false`).
3. The sidebar renders expanded.
Result: Acceptable — `"false"` is the default; the catch-all preserves the current state without error.

### F2: restore_state arrives with sidebar_collapsed nil
Condition: First-time operator; no localStorage entry for sidebar_collapsed.
Steps:
1. `maybe_restore(socket, :sidebar_collapsed, nil)` hits the nil-matching clause.
2. `:sidebar_collapsed` is left as `false`.
Result: Sidebar renders expanded (default behavior).

## Gherkin Scenarios

### S1: Clicking toggle collapses expanded sidebar
```gherkin
Scenario: Toggling sidebar from expanded to collapsed persists state
  Given sidebar_collapsed is false
  When the operator triggers the "toggle_sidebar" event
  Then socket.assigns.sidebar_collapsed is true
  And push_event "filters_changed" is called with sidebar_collapsed "true"
```

### S2: Clicking toggle expands collapsed sidebar
```gherkin
Scenario: Toggling sidebar from collapsed to expanded persists state
  Given sidebar_collapsed is true
  When the operator triggers the "toggle_sidebar" event
  Then socket.assigns.sidebar_collapsed is false
  And push_event "filters_changed" is called with sidebar_collapsed "false"
```

### S3: restore_state with "true" restores collapsed sidebar
```gherkin
Scenario: Restored sidebar_collapsed "true" assigns true to socket
  Given the LiveView is mounted with sidebar_collapsed false
  When restore_state arrives with sidebar_collapsed "true"
  Then socket.assigns.sidebar_collapsed is true
```

### S4: restore_state with "false" leaves sidebar expanded
```gherkin
Scenario: restore_state with "false" does not change sidebar_collapsed
  Given the LiveView is mounted with sidebar_collapsed false
  When restore_state arrives with sidebar_collapsed "false"
  Then socket.assigns.sidebar_collapsed remains false
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/live/dashboard_live_test.exs` includes a test sending `"toggle_sidebar"` when `sidebar_collapsed: false` and asserts `socket.assigns.sidebar_collapsed == true` and `push_event("filters_changed", %{sidebar_collapsed: "true"})` is called (S1).
- [ ] A test sends `"toggle_sidebar"` when `sidebar_collapsed: true` and asserts `socket.assigns.sidebar_collapsed == false` (S2).
- [ ] A test simulates `restore_state` with `%{"sidebar_collapsed" => "true"}` and asserts `:sidebar_collapsed == true` (S3).
- [ ] A test simulates `restore_state` with `%{"sidebar_collapsed" => "false"}` and asserts `:sidebar_collapsed == false` (catch-all leaves unchanged) (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `"toggle_sidebar"` event (no params); `"restore_state"` event with `%{"sidebar_collapsed" => string}`
**Outputs:** Updated `:sidebar_collapsed` assign; `"filters_changed"` push event
**State changes:** `socket.assigns.sidebar_collapsed` boolean; localStorage sidebar key via hook

## Traceability
- Parent FR: [FR-1.7](../frds/FRD-001-navigation-view-architecture.md)
- ADR: [ADR-001](../../decisions/ADR-001-swarm-control-center-nav.md), [ADR-003](../../decisions/ADR-003-unified-control-plane.md), [ADR-008](../../decisions/ADR-008-default-view-evolution.md)
