# ICHOR IV (formerly Observatory) - Handoff

## Current Status: Template Color Migration Complete (2026-03-09)

### Just Completed

**Template Color Migration (1,171 references -> semantic tokens)**
- Added Tailwind v4 `@theme` block to `assets/css/app.css` registering `--ichor-*` tokens as Tailwind utilities
- 26 semantic color utilities: `text-high`, `text-default`, `text-low`, `text-muted`, `bg-base`, `bg-raised`, `bg-highlight`, `bg-surface`, `bg-overlay`, `border-border`, `border-border-subtle`, `text-brand`, `bg-brand`, `text-success`, `bg-success`, `text-error`, `bg-error`, `text-info`, `bg-info`, `text-interactive`, `bg-interactive`, plus muted/dim variants
- Added `--ichor-bg-highlight` token (zinc-700 area) for hover/active states
- Bulk perl replacement across all `.heex` + `.ex` files under `lib/observatory_web/`
- Color mapping: zinc-300/200/100 -> high, zinc-400 -> default, zinc-500 -> low, zinc-600/700 -> muted, zinc-900/950 -> base, zinc-800 -> raised, zinc-700 -> highlight, amber -> brand, emerald -> success, red -> error, blue -> info, indigo -> interactive
- 1 remaining: `bg-amber-950` in Archon system message (deferred to Archon CSS tokenization)

**Prior: Design Token System + Theme Foundation**
- 26 `--ichor-*` CSS custom properties, two themes (ICHOR IV dark + Swiss light)
- ~50 `ichor-*` component classes migrated to tokens
- `obs-*` -> `ichor-*` rename across CSS + 13 templates

### Previously Completed

**Archon Type IV Sovereign HUD Redesign**
- Centered 16:9 translucent glass panel, 3 tabs (Command/Chat/Reference), keyboard-driven

**Fleet Control Fixes (5 issues)**
- agent_index prop, shutdown/kill cleanup, pause/resume immediate update, focus slideout, HITL notification

**LiveView Performance Optimization (6 fixes)**
**Fleet Consistency Rewire + Legacy Elimination (tasks 42, 51)**
**DashboardLive refactor: 594 -> 164 lines (dispatch/3 pattern)**

### .env Setup
- `ANTHROPIC_API_KEY` in `.env` at project root
- Not auto-loaded -- `source .env` before `mix phx.server`

### Build Status
`mix compile --warnings-as-errors` -- CLEAN

### Next Steps
1. **Archon CSS tokenization**: Convert archon-* classes from hardcoded rgba() to `hsl(var(--ichor-*))`
2. **Workshop canvas tokenization**: Convert agent-node hardcoded hex colors to tokens
3. **Theme switcher UI**: Add toggle button in dashboard header
4. **Streams** (deferred): Convert events list to LiveView streams for render perf
5. **LiveComponents** (deferred): Isolate fleet tree, feed, inspector as stateful components

### Memories Server
- Running on port 4000 (must be running for Archon memory tools)
- Requires Docker: postgres (port 5434) + falkordb (port 6379)
- ONNX models on external drive: `/Volumes/T5/models/ONNX`
