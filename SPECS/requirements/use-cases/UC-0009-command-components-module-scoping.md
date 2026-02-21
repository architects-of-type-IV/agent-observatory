---
id: UC-0009
title: Scope agent derivation inside CommandComponents via collect_agents/3
status: draft
parent_fr: FR-1.9
adrs: [ADR-001, ADR-003, ADR-008]
---

# UC-0009: Scope Agent Derivation Inside CommandComponents via collect_agents/3

## Intent
`ObservatoryWeb.Components.CommandComponents` is the exclusive renderer of the `:command` view. It loads its HEEX templates from `command_components/` via `embed_templates`. The heavyweight `collect_agents/3` function runs inside the component, not in `prepare_assigns/1`, ensuring that agent derivation overhead is paid only when the operator is on the `:command` view, not on every server tick for every other view.

## Primary Actor
System

## Supporting Actors
- `ObservatoryWeb.Components.CommandComponents`
- `ObservatoryWeb.DashboardLive.prepare_assigns/1`
- `command_components/` HEEX template directory

## Preconditions
- The LiveView render has evaluated `view_mode == :command` as true.
- `@teams`, `@events`, and `@now` assigns are available.

## Trigger
`CommandComponents.command_view/1` is called by the `:command` branch of `DashboardLive`'s render function.

## Main Success Flow
1. The LiveView render dispatches to `CommandComponents.command_view/1` for `view_mode == :command`.
2. `command_view/1` calls `collect_agents/3` with the `teams`, `events`, and `now` assigns.
3. `collect_agents/3` builds the cluster hierarchy map.
4. The cluster hierarchy is passed as a local variable to the HEEX template loaded from `command_components/command_view.html.heex`.
5. The template renders using `embed_templates "command_components/*"`.
6. Agent derivation is never called for `:feed`, `:errors`, or any other view mode.

## Alternate Flows

### A1: CommandComponents renders with teams list only (no events)
Condition: `@events == []`.
Steps:
1. `collect_agents/3` receives empty events list.
2. The function derives agents from team membership data only, with no event enrichment.
3. Agent blocks render with static team data but no runtime status from events.

## Failure Flows

### F1: collect_agents/3 incorrectly moved to prepare_assigns/1
Condition: A developer relocates `collect_agents/3` to `prepare_assigns/1`.
Steps:
1. `prepare_assigns/1` runs on every server tick for all view modes.
2. Agent derivation incurs CPU cost even when the operator is on `:feed`.
3. FR-1.9 is violated.
Result: Detection: `grep -r "collect_agents" lib/observatory_web/live/` returns matches outside `command_components.ex`. CI must fail on this grep.

### F2: embed_templates path does not match actual directory
Condition: `embed_templates "command_components/*"` does not resolve to existing HEEX files.
Steps:
1. Compilation raises `File.Error` (no matching files).
2. The project fails to compile.
Result: `mix compile --warnings-as-errors` fails; caught before deployment.

## Gherkin Scenarios

### S1: collect_agents/3 is called inside command_view/1 render
```gherkin
Scenario: collect_agents/3 executes only during :command view rendering
  Given view_mode is :command
  And @teams and @events are non-empty
  When CommandComponents.command_view/1 is called
  Then collect_agents/3 is invoked with teams, events, and now
  And the cluster hierarchy is produced for template rendering
```

### S2: collect_agents/3 is absent from prepare_assigns/1
```gherkin
Scenario: collect_agents/3 is not referenced in prepare_assigns/1
  Given the codebase is compiled
  When grep searches lib/observatory_web/live/ for "collect_agents"
  Then no matches are found in any file under lib/observatory_web/live/
```

### S3: embed_templates loads command_components templates
```gherkin
Scenario: embed_templates resolves command_components directory at compile time
  Given lib/observatory_web/components/command_components/ contains .heex templates
  When mix compile runs
  Then compilation succeeds with no File.Error
  And command_view/1 function is defined in CommandComponents module
```

### S4: Empty events list does not crash collect_agents/3
```gherkin
Scenario: collect_agents/3 handles empty events without crash
  Given @teams is non-empty
  And @events is an empty list
  When CommandComponents.command_view/1 renders
  Then no crash occurs
  And agent blocks render with team-only data
```

## Acceptance Criteria
- [ ] `grep -r "collect_agents" lib/observatory_web/live/` returns zero matches (S2, enforced in CI).
- [ ] `mix test test/observatory_web/components/command_components_test.exs` includes a test calling `command_view/1` with non-empty teams/events and asserting the rendered HTML contains agent block elements (S1).
- [ ] `mix compile --warnings-as-errors` passes, confirming `embed_templates` resolves correctly (S3).
- [ ] A test calls `command_view/1` with `events: []` and asserts no exception is raised (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `teams` list, `events` list, `now` datetime (passed as assigns to `command_view/1`)
**Outputs:** Rendered HTML for the `:command` view
**State changes:** None (pure derivation and rendering)

## Traceability
- Parent FR: [FR-1.9](../frds/FRD-001-navigation-view-architecture.md)
- ADR: [ADR-001](../../decisions/ADR-001-swarm-control-center-nav.md), [ADR-003](../../decisions/ADR-003-unified-control-plane.md), [ADR-008](../../decisions/ADR-008-default-view-evolution.md)
