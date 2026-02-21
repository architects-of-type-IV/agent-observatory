---
id: UC-0132
title: Run mix clean before compiling after embed_templates mode change
status: draft
parent_fr: FR-5.8
adrs: [ADR-010]
---

# UC-0132: Run mix clean Before Compiling After embed_templates Mode Change

## Intent
Switching a component between `embed_templates` and inline `~H` (in either direction) leaves stale `.beam` files from the previous compilation. These stale files cause "function already defined" redefinition warnings on the next `mix compile`. Running `mix clean` before `mix compile` after any such transition eliminates the stale files and produces a clean build.

## Primary Actor
Developer

## Supporting Actors
- `mix clean` (clears `_build/` directory)
- `mix compile --warnings-as-errors`
- Elixir build system (`_build/` directory)

## Preconditions
- A component module has just been converted from `embed_templates` to inline `~H`, or vice versa.
- `_build/` contains `.beam` files from the previous compilation of that module.

## Trigger
A developer finishes editing the component and runs the build.

## Main Success Flow
1. Developer converts the component (e.g., removes `embed_templates`, adds inline `~H`).
2. Developer runs `mix clean` to clear stale `.beam` files.
3. Developer runs `mix compile --warnings-as-errors`.
4. Compilation succeeds with zero warnings.

## Alternate Flows

### A1: Clean build from scratch (no stale files)
Condition: The `_build/` directory was already clean before the change.
Steps:
1. `mix clean` is a no-op (nothing to clean).
2. `mix compile --warnings-as-errors` passes directly.
3. No redefinition warnings occur.

## Failure Flows

### F1: mix compile run without mix clean
Condition: Developer skips `mix clean` after changing `embed_templates` mode.
Steps:
1. Stale `.beam` files conflict with the newly compiled module.
2. `mix compile --warnings-as-errors` produces "function foo/1 is already defined" warnings.
3. Because `--warnings-as-errors` is used, the build fails.
4. Developer runs `mix clean && mix compile --warnings-as-errors`.
5. Compilation succeeds with zero warnings.
Result: The `--warnings-as-errors` flag catches the stale-beam problem before it reaches CI.

## Gherkin Scenarios

### S1: mix clean && mix compile succeeds after embed_templates to inline conversion
```gherkin
Scenario: Converting from embed_templates to inline ~H requires mix clean
  Given a component was using embed_templates with co-located .heex files
  When embed_templates is removed and templates are inlined as ~H blocks
  And mix clean is run before mix compile
  Then mix compile --warnings-as-errors succeeds with zero warnings
```

### S2: Skipping mix clean produces redefinition warnings
```gherkin
Scenario: Omitting mix clean after embed_templates change causes redefinition warnings
  Given a component was using embed_templates
  When embed_templates is removed without running mix clean
  And mix compile --warnings-as-errors is run
  Then compilation fails with function redefinition warnings
  When mix clean is run followed by mix compile --warnings-as-errors
  Then compilation succeeds with zero warnings
```

## Acceptance Criteria
- [ ] After any `embed_templates`-to-inline-`~H` conversion in the test environment, `mix clean && mix compile --warnings-as-errors` produces zero warnings (S1).
- [ ] `mix compile --warnings-as-errors` (without prior `mix clean`) after an `embed_templates` mode change produces at least one warning (demonstrating the stale-beam problem exists and is caught) (S2).

## Data
**Inputs:** `_build/` directory containing stale `.beam` files; updated `.ex` component file
**Outputs:** Clean `_build/` directory after `mix clean`; successful compilation after `mix compile`
**State changes:** `_build/` directory is cleared by `mix clean` and repopulated by `mix compile`

## Traceability
- Parent FR: [FR-5.8](../frds/FRD-005-code-architecture-patterns.md)
- ADR: [ADR-010](../../decisions/ADR-010-component-file-split.md)
