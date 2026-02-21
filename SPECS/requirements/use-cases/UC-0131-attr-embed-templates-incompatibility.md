---
id: UC-0131
title: Avoid embed_templates on components with attr declarations
status: draft
parent_fr: FR-5.7
adrs: [ADR-010]
---

# UC-0131: Avoid embed_templates on Components with attr Declarations

## Intent
The Phoenix `attr` macro and `embed_templates` are mutually incompatible: using both in the same module produces a compile-time "could not define attributes" error. Components that declare typed attributes with `attr` must use inline `~H` sigils. If such a component grows large, it must be broken into smaller components rather than using `embed_templates`.

## Primary Actor
Developer

## Supporting Actors
- Phoenix `attr` macro
- `embed_templates` macro
- `mix compile --warnings-as-errors` (produces compile-time error on violation)

## Preconditions
- A Phoenix Component module uses one or more `attr` declarations.
- A developer is considering adding `embed_templates` to split the module.

## Trigger
A developer considers splitting an `attr`-using component module by adding `embed_templates`.

## Main Success Flow
1. The developer identifies that the component uses `attr` declarations.
2. The developer recognises the incompatibility with `embed_templates`.
3. Instead of splitting with `embed_templates`, the developer breaks the component into smaller sub-components, each small enough to stay under 30 lines with inline `~H`.
4. `mix compile --warnings-as-errors` passes with zero warnings.

## Alternate Flows

### A1: Removing attr declarations to enable embed_templates
Condition: The `attr` declarations are not used for type checking but only for documentation.
Steps:
1. Developer removes the `attr` declarations.
2. Template accesses `@assigns` directly instead of typed attributes.
3. `embed_templates` is added.
4. `mix compile --warnings-as-errors` passes.

## Failure Flows

### F1: embed_templates added to a module with attr declarations
Condition: A developer adds `embed_templates "*.heex"` to a module that has `attr :items, :list`.
Steps:
1. `mix compile` produces a compile-time error: "could not define attributes for component ... when using embed_templates".
2. The developer removes `embed_templates` and reverts to inline `~H`.
3. If the module is too large, it is broken into smaller sub-components.
4. `mix compile --warnings-as-errors` passes after correction.
Result: The compile error acts as an automatic guard; no runtime regression possible.

## Gherkin Scenarios

### S1: Module with attr declarations uses inline ~H without embed_templates
```gherkin
Scenario: An attr-declaring component uses inline ~H and compiles cleanly
  Given a button component declares attr :label, :string
  And its 12-line template uses an inline ~H sigil
  When mix compile --warnings-as-errors runs
  Then compilation succeeds with zero warnings
  And no embed_templates call is present in the module
```

### S2: Adding embed_templates to attr module causes compile error
```gherkin
Scenario: embed_templates on an attr-using module produces a compile-time error
  Given a component module contains attr :items, :list and embed_templates "*.heex"
  When mix compile runs
  Then compilation fails with a "could not define attributes" error
  When embed_templates is removed and inline ~H is used instead
  Then mix compile --warnings-as-errors succeeds
```

### S3: Large attr-using component is broken into sub-components
```gherkin
Scenario: A large attr-declaring component is split into smaller sub-components
  Given a component with attr declarations is 80 lines
  When the developer extracts half the logic into a new sub-component
  Then each resulting component is under 30 lines
  And both use inline ~H (no embed_templates)
  And mix compile --warnings-as-errors passes
```

## Acceptance Criteria
- [ ] `grep -l "attr " lib/observatory_web/components/*.ex | xargs grep -l "embed_templates"` returns no files (no module uses both) (S1, S2).
- [ ] All modules using `embed_templates` have zero `attr` declarations (verified by static grep) (S2).
- [ ] `mix compile --warnings-as-errors` passes with the current component set (S1).

## Data
**Inputs:** Component module source; presence of `attr` and `embed_templates` macros
**Outputs:** Either: inline `~H` component with `attr`; or `embed_templates` component without `attr`
**State changes:** No runtime state; compile-time code generation only

## Traceability
- Parent FR: [FR-5.7](../frds/FRD-005-code-architecture-patterns.md)
- ADR: [ADR-010](../../decisions/ADR-010-component-file-split.md)
