---
id: UC-0003
title: Persist view mode to localStorage on every view change
status: draft
parent_fr: FR-1.3
adrs: [ADR-001, ADR-003, ADR-008]
---

# UC-0003: Persist View Mode to localStorage on Every View Change

## Intent
Whenever the operator changes view mode through a keyboard shortcut or tab click, the LiveView pushes a `"view_mode_changed"` JS event to the client. The `StatePersistence` hook writes the new mode string to `localStorage["observatory:view_mode"]`, ensuring the selection survives page reloads. Cross-view jump navigations intentionally bypass this path and do not update localStorage.

## Primary Actor
Operator

## Supporting Actors
- `ObservatoryWeb.DashboardFilterHandlers.handle_set_view/2`
- `StatePersistence` JS hook
- `ObservatoryWeb.DashboardNavigationHandlers` (excluded path)

## Preconditions
- The LiveView is mounted and `handle_set_view/2` is the active event handler for `"set_view"`.
- The `StatePersistence` hook is attached to `id="view-mode-toggle"`.

## Trigger
`handle_set_view/2` successfully assigns a new `:view_mode` and calls `push_event("view_mode_changed", %{view_mode: mode_string})`.

## Main Success Flow
1. The operator presses `2` (or clicks the Command tab).
2. `KeyboardShortcuts` (or phx-click) pushes `"set_view"` with `mode: "command"`.
3. `handle_set_view/2` assigns `:command` to `:view_mode`.
4. `handle_set_view/2` calls `push_event("view_mode_changed", %{view_mode: "command"})`.
5. The `StatePersistence` hook receives `"view_mode_changed"` and writes `"command"` to `localStorage["observatory:view_mode"]`.
6. On the next page load, `restore_state` reads `"command"` and restores it.

## Alternate Flows

### A1: Cross-view jump navigation does not persist to localStorage
Condition: `DashboardNavigationHandlers` handles `"jump_to_feed"` and assigns `:feed` directly without calling `handle_set_view/2`.
Steps:
1. `handle_event("jump_to_feed", %{"session_id" => sid}, socket)` assigns `:view_mode` to `:feed`.
2. `push_event("view_mode_changed", ...)` is NOT called.
3. The `StatePersistence` hook does not receive `"view_mode_changed"`.
4. localStorage retains the previously persisted mode (e.g., `"command"`).
5. On the next page load, `:command` is restored, not `:feed`.

## Failure Flows

### F1: StatePersistence hook not attached to DOM
Condition: The element `id="view-mode-toggle"` is absent or the hook binding is missing.
Steps:
1. `push_event("view_mode_changed", ...)` fires from the server.
2. No hook listener is registered; the event is silently dropped by Phoenix.
3. localStorage is not updated.
Result: The mode is not persisted; the next reload restores the previously stored mode or defaults to `:overview`.

## Gherkin Scenarios

### S1: Keyboard shortcut triggers localStorage persistence
```gherkin
Scenario: Pressing a keyboard shortcut persists the view mode to localStorage
  Given the LiveView is mounted and StatePersistence hook is attached
  And localStorage["observatory:view_mode"] is "overview"
  When the operator presses "2" to switch to :command view
  Then handle_set_view/2 pushes event "view_mode_changed" with view_mode "command"
  And localStorage["observatory:view_mode"] is written as "command"
```

### S2: Jump navigation does not update localStorage
```gherkin
Scenario: Cross-view jump navigation does not push view_mode_changed
  Given the LiveView is mounted with view_mode :command
  And localStorage["observatory:view_mode"] is "command"
  When a "jump_to_feed" event fires with session_id "abc-123"
  Then view_mode is assigned :feed
  And no "view_mode_changed" event is pushed to the client
  And localStorage["observatory:view_mode"] remains "command"
```

### S3: Restored mode on next page load
```gherkin
Scenario: Previously persisted mode is restored on page reload
  Given localStorage["observatory:view_mode"] is "command"
  When the operator reloads the page and DashboardLive mounts
  And StatePersistence pushes restore_state with view_mode "command"
  Then socket.assigns.view_mode equals :command
```

### S4: Missing StatePersistence hook silently drops persistence
```gherkin
Scenario: Missing hook causes silent persistence failure without crash
  Given the StatePersistence hook is not attached to the DOM
  When handle_set_view/2 pushes "view_mode_changed" with view_mode "feed"
  Then the LiveView process does not crash
  And localStorage is not updated
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/live/dashboard_live_test.exs` verifies that `handle_set_view/2` calls `push_event("view_mode_changed", %{view_mode: "command"})` when the mode changes to `:command` (S1).
- [ ] A test verifies that `handle_event("jump_to_feed", ...)` does NOT call `push_event("view_mode_changed", ...)` (S2).
- [ ] A test simulates `restore_state` with `%{"view_mode" => "command"}` after mount and asserts `:view_mode` is `:command` (S3).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `view_mode` string from `handle_set_view/2`
**Outputs:** `"view_mode_changed"` JS push event with `%{view_mode: string}`
**State changes:** `localStorage["observatory:view_mode"]` written by `StatePersistence` hook on client

## Traceability
- Parent FR: [FR-1.3](../frds/FRD-001-navigation-view-architecture.md)
- ADR: [ADR-001](../../decisions/ADR-001-swarm-control-center-nav.md), [ADR-003](../../decisions/ADR-003-unified-control-plane.md), [ADR-008](../../decisions/ADR-008-default-view-evolution.md)
