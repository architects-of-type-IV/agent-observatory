---
id: UC-0128
title: Split an oversized component module using embed_templates
status: draft
parent_fr: FR-5.4
adrs: [ADR-010]
---

# UC-0128: Split an Oversized Component Module Using embed_templates

## Intent
When a Phoenix Component module reaches or exceeds 300 lines, it is split: logic and helpers remain in the `.ex` file, and HEEx templates are extracted to co-located `.heex` files. The `.ex` file uses `embed_templates` to generate function heads from the `.heex` filenames. This restores the module to a manageable size and keeps rendering logic in discrete files.

## Primary Actor
Developer

## Supporting Actors
- `Phoenix.Component` (provides `embed_templates/1` macro)
- `.heex` template files (co-located with the `.ex` file)
- `mix compile --warnings-as-errors` (verification gate)

## Preconditions
- A Phoenix Component module is at or above 300 lines.
- The module does not use `attr` declarations (see UC-0131 for the attr constraint).
- The module's templates can be expressed as standalone HEEx files.

## Trigger
Code review flags the module as oversized, or a developer notices the line count during work.

## Main Success Flow
1. Developer counts module lines and confirms it exceeds 300.
2. Each large inline `~H` block is extracted to a `.heex` file named after the component function (e.g., `parent_segment.heex`).
3. The `.ex` file retains `use Phoenix.Component`, imports, dispatch functions, and helper functions.
4. `embed_templates "*.heex"` (or a pattern matching the extracted files) is added to the `.ex` file.
5. `mix clean && mix compile --warnings-as-errors` is run (clean required to clear stale `.beam` files).
6. Zero warnings; the module is now under 300 lines.

## Alternate Flows

### A1: Template already small (no extraction needed for that function)
Condition: Some component functions have templates shorter than ~20 lines.
Steps:
1. Those templates may remain inline as `~H` sigils.
2. Only the largest templates are extracted to `.heex` files.
3. The total `.ex` file drops below 300 lines.

## Failure Flows

### F1: mix compile run without mix clean after embed_templates change
Condition: Developer runs `mix compile` without prior `mix clean` after switching to `embed_templates`.
Steps:
1. Stale `.beam` files from the previous compilation cause "function already defined" redefinition warnings.
2. `mix compile --warnings-as-errors` fails.
3. Developer runs `mix clean && mix compile --warnings-as-errors`.
4. Compilation succeeds with zero warnings.
Result: Always run `mix clean` when changing to/from `embed_templates`.

### F2: Module exceeds 300 lines but no split is attempted
Condition: A 600-line component is committed without splitting.
Steps:
1. Code review identifies the violation.
2. The developer splits using `embed_templates`.
3. `mix compile --warnings-as-errors` passes after split.

## Gherkin Scenarios

### S1: Oversized module is split and drops below 300 lines
```gherkin
Scenario: A 480-line component module is split using embed_templates
  Given FeedComponents.ex is 480 lines
  And it contains 6 large inline ~H blocks
  When each ~H block is extracted to a .heex file
  And embed_templates is added to the .ex file
  And mix clean && mix compile --warnings-as-errors is run
  Then FeedComponents.ex is under 300 lines
  And the 6 .heex files exist alongside the .ex file
  And compilation succeeds with zero warnings
```

### S2: mix clean required after embed_templates switch
```gherkin
Scenario: Running mix compile without mix clean produces redefinition warnings
  Given a component was previously compiled with inline ~H templates
  When embed_templates is added without running mix clean first
  And mix compile runs
  Then redefinition warnings appear
  When mix clean is run followed by mix compile --warnings-as-errors
  Then compilation succeeds with zero warnings
```

## Acceptance Criteria
- [ ] All Phoenix Component modules in `lib/observatory_web/components/` have fewer than 300 lines (verified by `wc -l lib/observatory_web/components/*.ex`) (S1).
- [ ] `mix clean && mix compile --warnings-as-errors` passes with zero warnings after any `embed_templates` addition (S1, S2).
- [ ] Each `.heex` file co-located with a split `.ex` file is listed by `ls lib/observatory_web/components/*.heex` (S1).

## Data
**Inputs:** Oversized `.ex` component file; inline `~H` template blocks
**Outputs:** Reduced-size `.ex` file with `embed_templates`; one or more `.heex` template files
**State changes:** Source tree gains `.heex` files; `.ex` file shrinks below 300 lines

## Traceability
- Parent FR: [FR-5.4](../frds/FRD-005-code-architecture-patterns.md)
- ADR: [ADR-010](../../decisions/ADR-010-component-file-split.md)
