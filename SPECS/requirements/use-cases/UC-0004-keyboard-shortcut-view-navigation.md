---
id: UC-0004
title: Navigate to view mode via numeric keyboard shortcut
status: draft
parent_fr: FR-1.4
adrs: [ADR-001, ADR-003, ADR-008]
---

# UC-0004: Navigate to View Mode via Numeric Keyboard Shortcut

## Intent
The `KeyboardShortcuts` JS hook intercepts numeric key presses on the dashboard root element and pushes `"set_view"` events to the server. This use case defines the full mapping from key press to view mode assignment, including the guards that prevent the hook from firing inside text inputs and when modifier keys are held.

## Primary Actor
Operator

## Supporting Actors
- `KeyboardShortcuts` JS hook (attached to `id="dashboard-root"`)
- `ObservatoryWeb.DashboardFilterHandlers.handle_set_view/2`

## Preconditions
- The LiveView is mounted.
- The `KeyboardShortcuts` hook is bound to `id="dashboard-root"`.
- The focused element is NOT an `INPUT` or `TEXTAREA`.
- Neither `e.metaKey` nor `e.ctrlKey` is held.

## Trigger
The operator presses a numeric key (`1`–`9` or `0`) with document body focus.

## Main Success Flow
1. Operator presses `6` with focus on document body.
2. `KeyboardShortcuts` receives the keydown event.
3. The hook checks: `e.target.tagName === "INPUT"` → false; `e.metaKey || e.ctrlKey` → false.
4. The hook maps key `"6"` to index 5, resolves to `"feed"`.
5. The hook calls `this.pushEvent("set_view", {mode: "feed"})`.
6. `handle_set_view/2` converts `"feed"` to `:feed` and assigns it.
7. The Feed view renders.

## Alternate Flows

### A1: Key `0` maps to :errors (index 9 alias)
Condition: Operator presses `0`.
Steps:
1. The hook maps `"0"` to index 9, resolves to `"errors"`.
2. `handle_set_view/2` assigns `:errors`.
3. The Errors view renders.

### A2: `?` key opens shortcuts help modal
Condition: Operator presses `?`.
Steps:
1. The hook pushes `"toggle_shortcuts_help"` event.
2. The server toggles the `@show_shortcuts_help` assign.
3. The help overlay renders or dismisses.

### A3: `Escape` key pushes keyboard_escape
Condition: Operator presses `Escape`.
Steps:
1. The hook pushes `"keyboard_escape"` event.
2. The server clears modal or selection state as appropriate.

### A4: `f` key focuses search input without server event
Condition: Operator presses `f`.
Steps:
1. The hook calls `document.querySelector('input[name="q"]').focus()`.
2. No `pushEvent` call is made.
3. No server-side state changes.

## Failure Flows

### F1: Key pressed while INPUT is focused
Condition: Operator presses `6` while cursor is inside the search input.
Steps:
1. `KeyboardShortcuts` fires the keydown handler.
2. `e.target.tagName === "INPUT"` evaluates true.
3. The hook returns early without calling `pushEvent`.
Result: No `"set_view"` event is sent; view mode is unchanged.

### F2: Key pressed with metaKey held
Condition: Operator presses `Cmd+6` (e.g., to switch browser tabs).
Steps:
1. `e.metaKey` evaluates true.
2. The hook returns early without calling `pushEvent`.
Result: No `"set_view"` event is sent; the browser handles `Cmd+6` natively.

## Gherkin Scenarios

### S1: Numeric key navigates to mapped view
```gherkin
Scenario: Pressing "6" with body focus navigates to :feed
  Given the KeyboardShortcuts hook is bound to dashboard-root
  And the focused element is the document body
  When the operator presses "6"
  Then pushEvent is called with mode "feed"
  And view_mode is assigned :feed
```

### S2: Key 0 maps to :errors
```gherkin
Scenario: Pressing "0" navigates to :errors
  Given the KeyboardShortcuts hook is active
  And no modifier keys are held
  When the operator presses "0"
  Then pushEvent is called with mode "errors"
  And view_mode is assigned :errors
```

### S3: Key press inside INPUT is suppressed
```gherkin
Scenario: Pressing a numeric key inside a text input is ignored
  Given the focused element is an INPUT with name "q"
  When the operator presses "6"
  Then no pushEvent is called
  And view_mode is unchanged
```

### S4: Key press with metaKey held is suppressed
```gherkin
Scenario: Pressing a numeric key with metaKey held is ignored
  Given the operator holds the metaKey modifier
  When the operator presses "6"
  Then no pushEvent is called
  And view_mode is unchanged
```

## Acceptance Criteria
- [ ] A JavaScript unit test (or Playwright test) verifies that pressing each key `1`–`9` and `0` on document body calls `pushEvent("set_view", {mode: <expected>})` with the correct mode string per FR-1.4 table (S1, S2).
- [ ] A test verifies that pressing `6` while an INPUT is focused does NOT call `pushEvent` (S3).
- [ ] A test verifies that pressing `6` with `metaKey: true` does NOT call `pushEvent` (S4).
- [ ] `mix test test/observatory_web/live/dashboard_live_test.exs` includes a test that sends `"set_view"` with mode `"feed"` and asserts `view_mode == :feed` (server-side validation of S1).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Keydown event (`key`, `metaKey`, `ctrlKey`, `target.tagName`)
**Outputs:** `pushEvent("set_view", %{mode: string})` or `pushEvent("toggle_shortcuts_help")` or `pushEvent("keyboard_escape")`
**State changes:** `socket.assigns.view_mode` updated via `handle_set_view/2`

## Traceability
- Parent FR: [FR-1.4](../frds/FRD-001-navigation-view-architecture.md)
- ADR: [ADR-001](../../decisions/ADR-001-swarm-control-center-nav.md), [ADR-003](../../decisions/ADR-003-unified-control-plane.md), [ADR-008](../../decisions/ADR-008-default-view-evolution.md)
