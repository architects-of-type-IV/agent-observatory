---
id: UC-0005
title: Render navigation tab bar with active state and error badge
status: draft
parent_fr: FR-1.5
adrs: [ADR-001, ADR-003, ADR-008]
---

# UC-0005: Render Navigation Tab Bar with Active State and Error Badge

## Intent
The navigation bar renders all canonical view mode tabs as clickable buttons. The active tab receives distinct CSS classes to indicate selection. The `:errors` tab renders a red numeric badge when errors exist. The `:overview` tab renders a pipeline progress counter when pipeline tasks are in flight. This use case validates the conditional rendering logic for these decorations.

## Primary Actor
Operator

## Supporting Actors
- `ObservatoryWeb.DashboardLive` (assigns `@view_mode`, `@errors`, `@swarm_state`)
- Navigation bar HEEX template (`id="view-mode-toggle"`)

## Preconditions
- The LiveView is mounted and rendering.
- `@view_mode`, `@errors`, and `@swarm_state` assigns are populated.

## Trigger
Any LiveView re-render that includes the navigation bar (mount, view mode change, or swarm state update).

## Main Success Flow
1. The LiveView renders with `@view_mode = :command` and `@errors = [e1, e2, e3]`.
2. Each tab button is rendered with `phx-click="set_view"` and `phx-value-mode`.
3. The `:command` tab receives CSS classes `bg-zinc-700 text-zinc-200 shadow-sm`.
4. All other tabs receive `text-zinc-500 hover:text-zinc-300`.
5. The `:errors` tab renders a red badge with the count `3`.
6. The `:overview` tab does not render a pipeline counter (because `@swarm_state.pipeline.total == 0`).

## Alternate Flows

### A1: :overview tab shows pipeline progress counter
Condition: `@swarm_state.pipeline.total > 0`.
Steps:
1. The `:overview` tab renders a `(completed/total)` counter inline with the tab label.
2. The counter reflects the current pipeline state (e.g., `(4/10)`).

### A2: Zero errors, no red badge
Condition: `@errors == []`.
Steps:
1. The `:if={mode == :errors && @errors != []}` guard evaluates false.
2. The `:errors` tab label renders without any badge or annotation.

## Failure Flows

### F1: @errors assign is nil instead of empty list
Condition: `@errors` is `nil` (assign not set by `prepare_assigns/1`).
Steps:
1. `@errors != []` evaluates true (nil is not `[]`).
2. The badge renders with `length(nil)` which raises `ArgumentError`.
3. The LiveView process crashes with a render error.
Result: Dashboard becomes unavailable until reconnected. Prevention: `prepare_assigns/1` MUST always assign `@errors` as a list, defaulting to `[]`.

## Gherkin Scenarios

### S1: Active tab receives active CSS classes
```gherkin
Scenario: Active view mode tab is highlighted
  Given the LiveView renders with view_mode :command
  When the navigation bar is rendered
  Then the :command tab element has CSS class "bg-zinc-700"
  And all other tabs do not have CSS class "bg-zinc-700"
```

### S2: Errors badge appears when errors list is non-empty
```gherkin
Scenario: Non-empty errors list renders a red badge on :errors tab
  Given @errors contains 3 error events
  And view_mode is :command
  When the navigation bar is rendered
  Then the :errors tab renders a badge with text "3"
  And the badge element has a red color class
```

### S3: Errors badge is absent when errors list is empty
```gherkin
Scenario: Empty errors list renders no badge on :errors tab
  Given @errors is an empty list
  When the navigation bar is rendered
  Then the :errors tab renders no badge element
```

### S4: Overview tab shows pipeline counter when pipeline is active
```gherkin
Scenario: Active pipeline renders progress counter on :overview tab
  Given @swarm_state.pipeline.total is 10
  And @swarm_state.pipeline.completed is 4
  When the navigation bar is rendered
  Then the :overview tab renders "(4/10)" inline with the label
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/live/dashboard_live_test.exs` includes a rendered HTML assertion that the `:command` tab contains `"bg-zinc-700"` when `view_mode` is `:command` (S1).
- [ ] A test renders with `errors: [%{}, %{}, %{}]` and asserts the rendered HTML contains a badge element with text `"3"` adjacent to the errors tab (S2).
- [ ] A test renders with `errors: []` and asserts no badge element is present in the errors tab HTML (S3).
- [ ] A test renders with `swarm_state.pipeline = %{total: 10, completed: 4}` and asserts the overview tab HTML contains `"4/10"` (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `@view_mode` atom, `@errors` list, `@swarm_state.pipeline` map
**Outputs:** Rendered HTML nav bar with conditional active classes and badges
**State changes:** None (pure rendering)

## Traceability
- Parent FR: [FR-1.5](../frds/FRD-001-navigation-view-architecture.md)
- ADR: [ADR-001](../../decisions/ADR-001-swarm-control-center-nav.md), [ADR-003](../../decisions/ADR-003-unified-control-plane.md), [ADR-008](../../decisions/ADR-008-default-view-evolution.md)
