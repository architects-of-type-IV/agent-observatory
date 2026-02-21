---
id: UC-0001
title: Validate and assign canonical view mode atom from set_view event
status: draft
parent_fr: FR-1.1
adrs: [ADR-001, ADR-003, ADR-008]
---

# UC-0001: Validate and Assign Canonical View Mode Atom from set_view Event

## Intent
When a client pushes a `"set_view"` event, `DashboardFilterHandlers.handle_set_view/2` converts the incoming string to an existing atom using `String.to_existing_atom/1` and assigns it to the `:view_mode` socket assign. This use case covers both the happy path (a recognized mode string) and the failure path (an unrecognized string that would raise `ArgumentError`) to ensure the LiveView process never crashes on invalid input.

## Primary Actor
Operator

## Supporting Actors
- `ObservatoryWeb.DashboardFilterHandlers`
- `ObservatoryWeb.DashboardLive` (socket assign owner)

## Preconditions
- The LiveView process is mounted and has a valid `:view_mode` assign.
- The `KeyboardShortcuts` or a tab button has generated a `"set_view"` event with a `phx-value-mode` string.

## Trigger
A `phx-click="set_view"` button click or a `KeyboardShortcuts` hook push delivers `handle_event("set_view", %{"mode" => mode_string}, socket)` to `DashboardLive`.

## Main Success Flow
1. `DashboardFilterHandlers.handle_set_view/2` receives `%{"mode" => "command"}`.
2. `String.to_existing_atom("command")` returns `:command` (atom was defined at compile time).
3. The handler assigns `:command` to `:view_mode` on the socket.
4. The LiveView re-renders with the Command view.

## Alternate Flows

### A1: Valid atom string for any other canonical mode
Condition: `mode_string` is one of `"overview"`, `"pipeline"`, `"agents"`, `"protocols"`, `"feed"`, `"tasks"`, `"messages"`, `"errors"`, `"analytics"`, `"timeline"`, `"teams"`, `"agent_focus"`.
Steps:
1. `String.to_existing_atom/1` succeeds.
2. The returned atom is assigned to `:view_mode`.
3. The corresponding view renders.

## Failure Flows

### F1: Unrecognized mode string raises ArgumentError
Condition: `mode_string` is `"unknown_mode"` or any string whose atom was never defined at compile time.
Steps:
1. `String.to_existing_atom("unknown_mode")` raises `ArgumentError`.
2. The `rescue ArgumentError` block in `DashboardUIHandlers.maybe_restore/3` catches the error (or the analogous rescue in `handle_set_view/2`).
3. The socket is returned unchanged; `:view_mode` retains its prior value.
4. No LiveView process crash occurs.
Result: The operator remains on the current view; no error flash is shown.

### F2: Empty string mode value
Condition: `mode_string` is `""` or `nil`.
Steps:
1. `String.to_existing_atom("")` raises `ArgumentError`.
2. The rescue block catches it.
3. `:view_mode` remains unchanged.
Result: View mode is unchanged; process remains alive.

## Gherkin Scenarios

### S1: Valid mode string produces atom assignment
```gherkin
Scenario: Recognized mode string is converted to atom and assigned
  Given the LiveView is mounted with view_mode :overview
  When a "set_view" event arrives with mode "command"
  Then view_mode is assigned :command
  And the Command view is rendered
```

### S2: Alternate canonical mode is accepted
```gherkin
Scenario: All canonical mode strings are accepted
  Given the LiveView is mounted with view_mode :overview
  When a "set_view" event arrives with mode "feed"
  Then view_mode is assigned :feed
  And the Feed view is rendered
```

### S3: Unrecognized mode string does not crash the LiveView
```gherkin
Scenario: Unknown mode string is silently ignored
  Given the LiveView is mounted with view_mode :command
  When a "set_view" event arrives with mode "unknown_mode"
  Then view_mode remains :command
  And the LiveView process is still alive
```

### S4: Empty mode string is silently ignored
```gherkin
Scenario: Empty mode string is silently ignored
  Given the LiveView is mounted with view_mode :overview
  When a "set_view" event arrives with mode ""
  Then view_mode remains :overview
  And no crash occurs
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/live/dashboard_live_test.exs` passes a test that sends `"set_view"` with `mode: "command"` and asserts `socket.assigns.view_mode == :command` (S1).
- [ ] The same test file includes a parameterized assertion for all 13 canonical atoms defined in FR-1.1 (S2).
- [ ] A test sends `"set_view"` with `mode: "unknown_mode"` and asserts the LiveView process does not crash and `view_mode` is unchanged (S3).
- [ ] A test sends `"set_view"` with `mode: ""` and asserts `view_mode` is unchanged (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `%{"mode" => string}` event params
**Outputs:** Updated `:view_mode` assign on socket (or unchanged socket on failure)
**State changes:** `socket.assigns.view_mode` atom may change

## Traceability
- Parent FR: [FR-1.1](../frds/FRD-001-navigation-view-architecture.md)
- ADR: [ADR-001](../../decisions/ADR-001-swarm-control-center-nav.md), [ADR-003](../../decisions/ADR-003-unified-control-plane.md), [ADR-008](../../decisions/ADR-008-default-view-evolution.md)
