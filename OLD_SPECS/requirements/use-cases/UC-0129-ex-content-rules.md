---
id: UC-0129
title: Enforce content rules for the .ex side of a split component
status: draft
parent_fr: FR-5.5
adrs: [ADR-010]
---

# UC-0129: Enforce Content Rules for the .ex Side of a Split Component

## Intent
In a split component module, the `.ex` file is limited to: `use Phoenix.Component`, imports, `defdelegate` facades, helper functions used across templates, and multi-head pattern-matched dispatch functions. Large inline `~H` blocks that can be moved to `.heex` files must not remain in the `.ex` file.

## Primary Actor
Developer

## Supporting Actors
- Code review process
- `mix compile --warnings-as-errors` (catches syntax issues but not structural violations)
- `.heex` template files (the correct home for templates)

## Preconditions
- A component module has been or is being split using `embed_templates`.
- The `.ex` and `.heex` files are co-located.

## Trigger
A developer adds or reviews code in the `.ex` file of a split component module.

## Main Success Flow
1. The developer confirms the `.ex` file contains only: `use Phoenix.Component`, imports, `defdelegate` calls, helper functions, and dispatch `defp` functions.
2. No `~H` sigil block exceeding a few lines appears in the `.ex` file.
3. Any newly added rendering logic is placed in a new or existing `.heex` file.
4. `mix compile --warnings-as-errors` passes with zero warnings.

## Alternate Flows

### A1: Multi-head dispatch function must stay in .ex
Condition: A component has multiple pattern-matched heads like `defp segment(%{segment: %{type: :parent}} = assigns)`.
Steps:
1. The dispatch function head stays in the `.ex` file (cannot be in `.heex`).
2. The body of each head calls the corresponding `.heex`-backed function.
3. The `.ex` file remains under 300 lines.

## Failure Flows

### F1: Developer adds a 120-line ~H block to the .ex file
Condition: A new feed segment type is implemented as a large inline `~H` block in the `.ex` file.
Steps:
1. Code review identifies the inline block.
2. The block is extracted to a new `new_segment.heex` file.
3. `embed_templates` picks up the new file.
4. `mix compile --warnings-as-errors` passes after extraction.
Result: The `.ex` file returns to containing only the permitted content types.

## Gherkin Scenarios

### S1: Split .ex file contains only permitted content types
```gherkin
Scenario: The .ex file of a split component has no large inline ~H blocks
  Given DashboardFeedComponents.ex is split using embed_templates
  When the file is inspected for ~H sigil blocks
  Then no ~H block in DashboardFeedComponents.ex exceeds 10 lines
  And all rendering logic is in .heex files
  And the file contains use Phoenix.Component, imports, and helper functions
```

### S2: New rendering logic is placed in a .heex file not the .ex file
```gherkin
Scenario: A developer adds a new segment type to a split component
  Given DashboardFeedComponents uses embed_templates
  When a developer adds a new segment type requiring 80 lines of HEEx markup
  Then the markup is written to new_segment.heex
  And the .ex file gains only a dispatch function head referencing new_segment
  And mix compile --warnings-as-errors passes
```

## Acceptance Criteria
- [ ] `grep -c "~H" lib/observatory_web/components/dashboard_feed_components.ex` returns 0 or a very small number (indicating no large inline templates remain) (S1).
- [ ] All `.ex` component files in `lib/observatory_web/components/` that use `embed_templates` have zero `~H` blocks exceeding 10 lines (S1).
- [ ] `mix compile --warnings-as-errors` passes (S2).

## Data
**Inputs:** `.ex` file content during authoring or review
**Outputs:** `.ex` file containing only permitted constructs; new `.heex` files for any extracted templates
**State changes:** Source tree may gain new `.heex` files; `.ex` file content is pruned

## Traceability
- Parent FR: [FR-5.5](../frds/FRD-005-code-architecture-patterns.md)
- ADR: [ADR-010](../../decisions/ADR-010-component-file-split.md)
