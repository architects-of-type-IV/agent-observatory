# Phoenix Component Library Research

## Libraries Found

### SaladUI
- **URL**: https://github.com/bluzky/salad_ui
- **What it does**: Phoenix LiveView component library directly inspired by shadcn/UI. Provides 37 pre-built components (Button, Input, Card, Dialog, Dropdown, Tabs, Badge, Alert, etc.) styled with Tailwind CSS. Available as either a hex dependency (components come from the package) or via `mix salad.install` (copies source into your project for full customization). Supports color scheme selection.
- **Pros**: Complete component set, shadcn-compatible design language, local-copy mode gives full control, color scheme system.
- **Cons**: v1 beta, no unit tests on v1 components, external dependency in remote mode, limited active maintenance bandwidth.
- **Variant pattern**: Uses `attr :variant, :string, values: ~w(...), default: "default"` then a `button_variant/1` helper that returns a class string, composed with a `classes/1` utility that merges base + variant + user-supplied `@class`.

### PetalComponents
- **URL**: https://github.com/petalframework/petal_components
- **What it does**: Production-grade component library for the PETAL stack (Phoenix, Elixir, Tailwind, Alpine.js, LiveView). Comprehensive set including Button, Input, Form, Badge, Card, Table, Modal, Dropdown, Tabs, Breadcrumbs, Pagination, Avatar, Progress, Accordion, SlideOver.
- **Pros**: Actively maintained, production-proven, rich variant/size/color support, comprehensive docs at petal.build.
- **Cons**: CSS class-name convention (prefixes like `pc-button--primary-solid`) rather than raw Tailwind utilities in component source -- requires importing petal stylesheet. Less hackable for dense terminal-style UIs like Ichor.
- **Variant pattern**: `button_classes/1` helper builds a class list from `"pc-button"`, `"pc-button--{color}-{variant}"`, `"pc-button--{size}"` strings. Customization via `@layer components` overrides.

### phx_component_helpers
- **URL**: https://github.com/cblavier/phx_component_helpers / https://hexdocs.pm/phx_component_helpers/readme.html
- **What it does**: Utility library for building extensible Phoenix components without boilerplate. Helpers for class merging, attribute forwarding, and slot defaults.
- **Pros**: Lightweight, composable, fills the gap that Phoenix's `attr :rest, :global` doesn't fully cover for class merging.
- **Cons**: Adds a dependency; Phoenix 1.7+ `attr` system already solves most of the same problems natively.

### Phoenix Native Class Merging (no dep)
- **URL**: https://fly.io/phoenix-files/customizable-classes-lv-component/
- **Pattern**: Combine `attr :class, :string, default: nil` with list-based class interpolation: `class={["base-class", @class]}`. Phoenix renders the list, nil entries are ignored. Zero dependencies.

---

## Variant Pattern

The recommended idiomatic Phoenix pattern (no external deps) for variant-based components:

### Pattern A: Static class map (preferred for bounded variant sets)

```elixir
@doc """
Renders a badge with semantic color variants.

## Examples

    <.badge variant="success">Compiled</.badge>
    <.badge variant="error">Failed</.badge>
    <.badge variant="info">Proposed</.badge>
    <.badge variant="brand">Building</.badge>
    <.badge variant="default">Unknown</.badge>
"""
attr :variant, :string,
  values: ~w(default success error info brand warning),
  default: "default"
attr :class, :string, default: nil
slot :inner_block, required: true

def badge(assigns) do
  ~H"""
  <span class={[badge_class(@variant), @class]}>
    {render_slot(@inner_block)}
  </span>
  """
end

@badge_base "px-1.5 py-0.5 text-[9px] font-semibold rounded uppercase tracking-wider"

defp badge_class("success"), do: "#{@badge_base} bg-success/15 text-success"
defp badge_class("error"),   do: "#{@badge_base} bg-error/15 text-error"
defp badge_class("info"),    do: "#{@badge_base} bg-info/15 text-info"
defp badge_class("brand"),   do: "#{@badge_base} bg-brand/15 text-brand"
defp badge_class("warning"), do: "#{@badge_base} bg-warning/15 text-warning"
defp badge_class(_),         do: "#{@badge_base} bg-raised text-muted"
```

### Pattern B: Map lookup (SaladUI style, good for many variants + sizes combined)

```elixir
@variants %{
  "primary"   => "bg-brand text-white hover:bg-brand/90",
  "secondary" => "bg-raised text-default hover:bg-highlight",
  "ghost"     => "bg-transparent text-default hover:bg-surface",
  "danger"    => "bg-error text-white hover:bg-error/90",
  "outline"   => "border border-border-subtle bg-transparent hover:bg-surface"
}

@sizes %{
  "sm" => "px-2 py-0.5 text-[10px]",
  "md" => "px-2.5 py-1 text-[11px]",
  "lg" => "px-4 py-1.5 text-sm"
}

attr :variant, :string, values: ~w(primary secondary ghost danger outline), default: "secondary"
attr :size, :string, values: ~w(sm md lg), default: "md"
attr :class, :string, default: nil
attr :rest, :global, include: ~w(disabled phx-click phx-value-id phx-disable-with)
slot :inner_block, required: true

def button(assigns) do
  assigns = assign(assigns, :computed_class, [
    "font-semibold rounded transition-colors cursor-pointer",
    Map.get(@variants, assigns.variant, @variants["secondary"]),
    Map.get(@sizes, assigns.size, @sizes["md"]),
    assigns.class
  ])

  ~H"""
  <button class={@computed_class} {@rest}>
    {render_slot(@inner_block)}
  </button>
  """
end
```

### Key Rules

1. **Never interpolate dynamic values into Tailwind class strings** -- Tailwind's JIT scanner is static. `"text-#{@color}"` will NOT be included in the CSS bundle. Use complete class strings in `defp` helpers or module attributes.

2. **Use `attr :variant, :string, values: ~w(...)`** -- this gives compile-time validation and documents the contract.

3. **Keep `attr :class, :string, default: nil`** for caller overrides. In the class list, `nil` is safely ignored.

4. **Compose with lists**: `class={["base", variant_class, @class]}` -- Phoenix handles list flattening and nil removal natively.

5. **Module attribute for base classes**: `@badge_base "..."` ensures the string is static and Tailwind-scannable.

6. **Pattern-match on assigns, not on strings in templates** -- use `defp` function heads for variant dispatch, not `if`/`cond` in HEEx.

---

## Current State

The codebase already has a rich component ecosystem under `lib/ichor_web/components/`:

### What exists

**Core Components** (`core_components.ex`):
- `button/1` -- has `attr :variant, :string, values: ~w(primary)` and a `%{"primary" => "btn-primary"}` map. Only one variant. Uses DaisyUI `btn` classes.
- `input/1` -- multi-clause by type (checkbox, select, textarea, text). Uses DaisyUI `input`, `select`, `textarea` classes.
- `flash/1` -- uses DaisyUI `alert`, `alert-info`, `alert-error`.
- `table/1`, `list/1`, `header/1`, `icon/1`.

**Presentation module** (`presentation.ex`):
- Rich class-returning functions: `archon_status_badge_class/1`, `health_bg_class/1`, `health_text_class/1`, `member_status_dot_class/1`, `task_status_text_class/1`, `severity_bg_class/1`, etc.
- These are pure functions returning Tailwind class strings -- the right approach.
- Problem: they return partial class strings that must be interpolated with string interpolation (`"#{class}"`) in templates, rather than being components.

**Pipeline Components** (`pipeline_components.ex`):
- `dag_border/3`, `dag_bg/1`, `dag_dot/1`, `task_badge_class/1`, `priority_color/1` -- all pattern-matching private helpers returning class strings. Correct pattern.

**MES Status Components** (`mes_status_components.ex`):
- `status_badge/1` -- multi-clause function that pattern-matches on `%{status: :atom}` assigns. Each clause renders its own `~H` block. This is the most duplicated pattern in the codebase.
- `action_button/1` -- same pattern.
- Problem: each clause is a separate `~H` render. A single component with a variant attribute and a class-returning helper would be 1/5 the code.

**Signal Feed Primitives** (`signal_feed/primitives.ex`):
- `kv/1`, `label/1`, `ts/1`, `id_short/1` -- small focused single-purpose components. The best pattern in the codebase.
- `label/1` accepts `attr :class, :string, default: "text-muted"` for color overrides. Close to optimal.

**FleetHelpers** (`fleet_helpers.ex`):
- `badge_class/1` -- pattern-match on role atom, returns class string. Pure function, correct.

### Duplication survey

The following badge/pill rendering pattern appears ~12 times across the codebase with slight variations:

```heex
<span class="px-1.5 py-0.5 text-[9px] font-semibold rounded bg-{color}/15 text-{color} uppercase tracking-wider">
```

Seen in:
- `mes_status_components.ex` (5 status_badge clauses)
- `pipeline_components.ex` (`task_badge_class` helper but inline in HEEX)
- `signal_components.ex` (category labels)
- `archon_components.ex` (status row)
- Various HEEX files for ad-hoc status rendering

The following small button pattern appears ~8 times:

```heex
<button class="px-2.5 py-1 text-[10px] font-semibold rounded bg-{color}/15 text-{color} hover:bg-{color}/25 transition-colors">
```

Seen in:
- `mes_status_components.ex` (`action_button` clauses)
- `mes_components.ex` (scheduler toggle)
- `signal_components.ex` (pause/clear buttons)
- `archon_components.ex` (close button, tab buttons)

---

## Recommended Approach

### Guiding principle

Do NOT adopt an external component library (SaladUI, PetalComponents). The codebase uses a dense terminal aesthetic with a custom design token system (DaisyUI + custom CSS variables: `text-high`, `text-muted`, `bg-raised`, `bg-surface`, `border-border`, etc.). External libraries assume different design tokens and would conflict.

Instead: **extract 5-8 primitive components** that consolidate the existing duplication, following the patterns already proven in `signal_feed/primitives.ex` and `pipeline_components.ex`.

### Structure

All primitives go in a new focused module:

```
lib/ichor_web/components/ichor/
  badge.ex          -- semantic color badge (status, priority, category)
  pill_button.ex    -- small action button (pick-up, load, toggle)
  status_dot.ex     -- already exists as member_status_dot
  model_badge.ex    -- already exists
  session_identity.ex -- already exists
```

Or consolidated into one `primitives.ex` (like `signal_feed/primitives.ex`) if they stay small.

### Component 1: `badge/1`

Replaces: `mes_status_components.ex` status_badge, `task_badge_class` pattern, `category_color` patterns.

```elixir
@moduledoc "Semantic status/category badge."

@base "px-1.5 py-0.5 text-[9px] font-semibold rounded uppercase tracking-wider"

attr :variant, :string,
  values: ~w(success error info brand warning muted),
  default: "muted"
attr :pulse, :boolean, default: false
attr :class, :string, default: nil
slot :inner_block, required: true

def badge(assigns) do
  ~H"""
  <span class={[@base, badge_variant(@variant), @class]}>
    <span :if={@pulse} class={"w-1 h-1 rounded-full animate-pulse #{dot_color(@variant)}"} />
    {render_slot(@inner_block)}
  </span>
  """
end

defp badge_variant("success"), do: "bg-success/15 text-success"
defp badge_variant("error"),   do: "bg-error/15 text-error"
defp badge_variant("info"),    do: "bg-info/15 text-info"
defp badge_variant("brand"),   do: "bg-brand/15 text-brand"
defp badge_variant("warning"), do: "bg-warning/15 text-warning"
defp badge_variant(_),         do: "bg-raised text-muted"
```

Usage replaces ~40 lines in `mes_status_components.ex`:

```heex
<.badge variant="success">Compiled</.badge>
<.badge variant="success" pulse={true}>Live</.badge>
<.badge variant="brand">Building</.badge>
<.badge variant="info">Proposed</.badge>
<.badge variant="error">Failed</.badge>
```

### Component 2: `pill_button/1`

Replaces: action buttons in `mes_status_components.ex`, toggle buttons in `mes_components.ex`, filter buttons in `signal_components.ex`.

```elixir
attr :variant, :string,
  values: ~w(brand success error warning info muted),
  default: "muted"
attr :active, :boolean, default: false
attr :class, :string, default: nil
attr :rest, :global, include: ~w(phx-click phx-value-id disabled type)
slot :inner_block, required: true

def pill_button(assigns) do
  ~H"""
  <button class={[pill_class(@variant, @active), @class]} {@rest}>
    {render_slot(@inner_block)}
  </button>
  """
end

@pill_base "px-2.5 py-1 text-[10px] font-semibold rounded transition-colors cursor-pointer"

defp pill_class(v, false), do: "#{@pill_base} #{pill_variant(v)}"
defp pill_class(v, true),  do: "#{@pill_base} #{pill_active(v)}"

defp pill_variant("brand"),   do: "bg-raised text-default hover:bg-brand/15 hover:text-brand"
defp pill_variant("success"), do: "bg-raised text-default hover:bg-success/15 hover:text-success"
# ...
```

### Component 3: `kv_chip/1`

Already exists as `IchorWeb.SignalFeed.Primitives.kv/1`. Promote to shared primitive location.

### Component 4: `status_dot/1`

Already exists as `IchorWeb.Components.Ichor.MemberStatusDot`. Generalize to accept any color variant, not just member status atoms.

### Folder target

Add a `IchorWeb.Components.Ichor.Primitives` module (or expand `IchorWeb.IchorComponents`) with the new badge and pill_button, then update `defdelegate` entries.

### What NOT to extract

- Complex multi-slot layout components (tabs, panels, sidebars) -- these are context-specific and low-duplication.
- Single-use components tied to one domain (archon_overlay, mes_components header).
- Anything using DaisyUI-specific classes (the core_components button/input use DaisyUI `btn`, `input`, `select` -- leave as-is).

---

## Reduction Potential

| Pattern | Current occurrences | After extraction | Lines saved |
|---------|-------------------|-----------------|-------------|
| Status badge span | ~12 | 12 `<.badge>` calls | ~80 lines |
| Pill action button | ~8 | 8 `<.pill_button>` calls | ~50 lines |
| `status_badge/1` multi-clause | 6 clauses * 5 lines | 1 function + 6 defp | ~20 lines |
| Duplicated `category_color/1` | 2 modules | shared helper | ~15 lines |
| **Total** | | | **~165 lines** |

The bigger gain is consistency: currently `bg-brand/15 text-brand` and `bg-brand/20 text-brand` both appear in different places for the same semantic intent. A single `badge_variant("brand")` definition eliminates the drift.

---

## Implementation Notes

### Tailwind static-class requirement

Tailwind JIT cannot scan dynamic class strings. All class values must appear as **complete static strings** in source files. This means:

```elixir
# CORRECT -- complete class string in defp
defp badge_variant("success"), do: "bg-success/15 text-success"

# WRONG -- Tailwind cannot see "bg-success/15"
defp badge_variant("success"), do: "bg-#{@color}/15 text-#{@color}"
```

If new variants are added, the complete class must be written out in the defp, never assembled from parts.

### DaisyUI vs raw Tailwind split

The codebase mixes both:
- `core_components.ex` uses DaisyUI (`btn`, `btn-primary`, `input`, `select`, `alert`, `table`, `fieldset`)
- Custom components use raw Tailwind utility classes

This split is intentional: DaisyUI for form infrastructure, raw Tailwind for domain-specific display components. Maintain this split -- do not introduce DaisyUI classes into new badge/pill_button primitives.

### Attr values validation

Always declare `values:` on variant attrs. This gives a compile-time error if a caller passes an invalid variant, catching bugs at build time rather than visually at runtime.

```elixir
attr :variant, :string, values: ~w(success error info brand warning muted), default: "muted"
```
