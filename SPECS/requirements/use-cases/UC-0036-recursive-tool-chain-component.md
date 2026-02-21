---
id: UC-0036
title: Render ToolChain component as collapsible group or inline single tool
status: draft
parent_fr: FR-2.12
adrs: [ADR-002]
---

# UC-0036: Render ToolChain Component as Collapsible Group or Inline Single Tool

## Intent
`ObservatoryWeb.Components.Feed.ToolChain` renders tool chain blocks. When a chain contains multiple pairs, it renders a collapsible header using `chain_tool_summary/1` output with child pairs rendered as individual tool execution blocks. When a chain contains exactly one pair, it renders the tool inline without a collapsible wrapper, avoiding unnecessary nesting for single-step operations. The component uses `embed_templates "tool_chain/*"`.

## Primary Actor
System

## Supporting Actors
- `ObservatoryWeb.Components.Feed.ToolChain`
- `ObservatoryWeb.DashboardFeedHelpers` (imported for chain helpers)
- `tool_chain/` HEEX template directory

## Preconditions
- A `{:tool_chain, pairs}` tuple is available from `build_segment_timeline/2`.
- The component is called by the feed template dispatcher.

## Trigger
The feed template encounters a `{:tool_chain, pairs}` tuple and calls `ToolChain.tool_chain/1` with the pairs list.

## Main Success Flow
1. `ToolChain.tool_chain/1` receives `pairs = [pair1, pair2, pair3]` (multiple pairs).
2. The component detects `length(pairs) > 1`.
3. A collapsible group header renders with `chain_tool_summary(pairs)` output (e.g., `"Bash x2, Read"`).
4. The header includes total duration from `chain_total_duration(pairs)`.
5. Expanding the header reveals three individual tool execution blocks rendered inline.

## Alternate Flows

### A1: Single-pair chain renders inline without collapsible wrapper
Condition: `pairs = [single_pair]` (one-element list).
Steps:
1. The component detects `length(pairs) == 1`.
2. No collapsible wrapper is rendered.
3. The single tool execution block renders directly inline.

## Failure Flows

### F1: embed_templates path for tool_chain does not resolve
Condition: No HEEX templates exist in `tool_chain/` directory.
Steps:
1. `embed_templates "tool_chain/*"` raises `File.Error` at compile time.
2. The module fails to compile.
Result: `mix compile --warnings-as-errors` fails; caught before deployment.

### F2: chain_tool_summary/1 called with empty pairs list
Condition: `{:tool_chain, []}` tuple somehow reaches the component (should not occur in normal flow).
Steps:
1. `chain_tool_summary([])` returns `""` or similar empty string.
2. The collapsible header renders with empty summary text.
3. No crash occurs.
Result: Graceful degradation; empty chains should not appear in practice.

## Gherkin Scenarios

### S1: Multi-pair chain renders collapsible header with summary
```gherkin
Scenario: Three tool pairs render a collapsible header
  Given a {:tool_chain, [pair1, pair2, pair3]} tuple where pairs are [Bash, Bash, Read]
  When ToolChain.tool_chain/1 renders
  Then a collapsible header element is present in the rendered HTML
  And the header text contains "Bash x2, Read"
  And three child tool execution blocks are rendered inside the collapsible
```

### S2: Single-pair chain renders inline without collapsible wrapper
```gherkin
Scenario: One tool pair renders inline without group header
  Given a {:tool_chain, [single_pair]} tuple
  When ToolChain.tool_chain/1 renders
  Then no collapsible wrapper element is present
  And the tool execution block renders directly inline
```

### S3: Collapsible header includes total duration
```gherkin
Scenario: Multi-pair chain header shows total duration
  Given a {:tool_chain, [pair1, pair2]} where pair1.duration_ms is 30 and pair2.duration_ms is 20
  When ToolChain.tool_chain/1 renders
  Then the header displays "50ms" or equivalent total duration
```

### S4: embed_templates compiles successfully for tool_chain directory
```gherkin
Scenario: tool_chain/ HEEX templates compile without error
  Given lib/observatory_web/components/feed/tool_chain/ contains .heex template files
  When mix compile runs
  Then no File.Error is raised
  And the ToolChain module is defined with tool_chain/1 function
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/components/feed/tool_chain_test.exs` includes a test rendering a three-pair chain and asserting the rendered HTML contains a collapsible element and the summary text `"Bash x2, Read"` (S1).
- [ ] A test rendering a one-element pair list asserts no collapsible wrapper element is present in the rendered HTML (S2).
- [ ] A test with pairs having `duration_ms` 30 and 20 asserts the header HTML contains a duration rendering of 50ms (S3).
- [ ] `mix compile --warnings-as-errors` passes, confirming `embed_templates` resolves correctly (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `pairs` list of tool pair maps (one or more)
**Outputs:** Rendered HTML: collapsible group (multi-pair) or inline tool block (single pair)
**State changes:** None (pure rendering)

## Traceability
- Parent FR: [FR-2.12](../frds/FRD-002-agent-block-feed.md)
- ADR: [ADR-002](../../decisions/ADR-002-agent-block-feed.md)
