---
id: UC-0006
title: Render unified command view with all operational panels
status: draft
parent_fr: FR-1.6
adrs: [ADR-001, ADR-003, ADR-008]
---

# UC-0006: Render Unified Command View with All Operational Panels

## Intent
When the operator navigates to `:command`, `command_view.html.heex` assembles fleet status bar, cluster hierarchy (project -> swarm -> agent), recent errors, recent messages, and alerts into a single scrollable surface. No further tab navigation is required to answer the question "do I need to intervene?" A right-side detail panel appears when an agent or task is selected.

## Primary Actor
Operator

## Supporting Actors
- `ObservatoryWeb.Components.CommandComponents`
- `command_view.html.heex` template
- `collect_agents/3` private function

## Preconditions
- The LiveView has `@view_mode == :command`.
- `@teams`, `@events`, and `@now` assigns are populated.

## Trigger
The `:command` view branch is evaluated during `DashboardLive` render, delegating to `CommandComponents.command_view/1`.

## Main Success Flow
1. The LiveView render evaluates `view_mode == :command`.
2. `CommandComponents.command_view/1` is called with `@teams`, `@events`, `@now`, and selection assigns.
3. `collect_agents/3` is called internally and builds the cluster hierarchy from teams and events.
4. `command_view.html.heex` renders: fleet status bar at the top, cluster cards (project -> swarm -> agent), recent errors section, recent messages section, and alerts panel.
5. All panels are visible in a single scrollable column.
6. The operator can assess swarm health without switching tabs.

## Alternate Flows

### A1: Agent selected — detail panel opens
Condition: `@selected_command_agent` is non-nil.
Steps:
1. The right-side detail panel renders with the selected agent's metadata.
2. The main scrollable column compresses to accommodate the panel.

### A2: Task selected — task detail panel opens
Condition: `@selected_command_task` is non-nil.
Steps:
1. The right-side detail panel renders with the selected task's fields.
2. Main column compresses.

### A3: No teams or events — empty state renders
Condition: `@teams == []` and `@events == []`.
Steps:
1. `collect_agents/3` returns an empty cluster hierarchy.
2. The command view renders empty cluster cards with a placeholder message.
3. Fleet status bar shows zero counts.

## Failure Flows

### F1: collect_agents/3 called from prepare_assigns/1 instead of CommandComponents
Condition: A developer moves `collect_agents/3` to `prepare_assigns/1` so it runs on every tick.
Steps:
1. Every LiveView tick (including `:feed` and `:errors` views) calls `collect_agents/3`.
2. Unnecessary CPU overhead on every server tick.
Result: This violates FR-1.6. The agent derivation MUST remain inside `CommandComponents`. Detection: `grep -r "collect_agents" lib/observatory_web/live/` MUST return zero results outside `command_components.ex`.

## Gherkin Scenarios

### S1: Command view renders all operational panels in one scroll
```gherkin
Scenario: Navigating to :command renders all panels without tab switching
  Given view_mode is :command
  And @teams contains at least one active team
  And @events contains recent events
  When command_view/1 renders
  Then the fleet status bar is present in the rendered HTML
  And the cluster hierarchy section is present
  And the recent errors section is present
  And the recent messages section is present
```

### S2: Agent selection opens detail panel
```gherkin
Scenario: Selecting an agent renders the right-side detail panel
  Given view_mode is :command
  And @selected_command_agent is a non-nil agent map
  When command_view/1 renders
  Then the detail panel element is present in the rendered HTML
  And the detail panel contains the agent's session_id
```

### S3: No teams or events renders empty state without crash
```gherkin
Scenario: Empty teams and events renders gracefully
  Given view_mode is :command
  And @teams is an empty list
  And @events is an empty list
  When command_view/1 renders
  Then no crash occurs
  And the fleet status bar renders with zero counts
```

### S4: collect_agents/3 is not called outside CommandComponents
```gherkin
Scenario: collect_agents/3 is scoped to CommandComponents only
  Given the codebase is compiled
  When grep searches for collect_agents in lib/observatory_web/live/
  Then no matches are found outside lib/observatory_web/components/command_components.ex
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/live/dashboard_live_test.exs` renders the dashboard with `view_mode: :command` and asserts the presence of fleet status bar, cluster, errors, messages, and alerts HTML elements (S1).
- [ ] A test renders with `selected_command_agent: %{session_id: "abc"}` and asserts the detail panel HTML is present (S2).
- [ ] A test renders with `teams: []` and `events: []` and asserts no crash and zero-count fleet status bar (S3).
- [ ] `grep -r "collect_agents" lib/observatory_web/live/` returns no matches (S4, enforced in CI).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `@teams` list, `@events` list, `@now` datetime, `@selected_command_agent`, `@selected_command_task`
**Outputs:** Rendered HTML containing all operational panels
**State changes:** None (pure rendering; `collect_agents/3` is read-only derivation)

## Traceability
- Parent FR: [FR-1.6](../frds/FRD-001-navigation-view-architecture.md)
- ADR: [ADR-001](../../decisions/ADR-001-swarm-control-center-nav.md), [ADR-003](../../decisions/ADR-003-unified-control-plane.md), [ADR-008](../../decisions/ADR-008-default-view-evolution.md)
