# ICHOR IV (formerly Observatory) - Handoff

## Current Status: Full Tokenization Complete (2026-03-09)

### Just Completed

**Archon CSS Tokenization**
- Converted all `archon-*` CSS classes from hardcoded `rgba()` to `hsl(var(--ichor-*) / opacity)`
- ~60 rgba() values mapped: zinc-900 -> bg, zinc-800 -> raised, zinc-700 -> border-subtle, amber -> brand, emerald -> success, black -> overlay
- Remaining @apply Tailwind classes also converted to token-based utilities
- `border-radius: 12px` -> `var(--ichor-radius-xl)`

**Workshop Canvas Tokenization**
- `@cap_colors` hex values -> `hsl(var(--ichor-role-*))` CSS custom properties
- Added 6 role accent tokens: `--ichor-role-{builder,scout,reviewer,lead,coordinator,default}` with Swiss overrides
- Canvas background `#09090b` -> `hsl(var(--ichor-bg))`, dot grid -> `hsl(var(--ichor-border-subtle))`
- `bg-[#18181b]` in team inspector -> `bg-base`

**Violet + Cyan Token Extension**
- Added `--ichor-violet` and `--ichor-cyan` tokens (28 + 55 references)
- Used for trace/relay (violet) and builder/channel (cyan) semantics
- Registered in @theme block as `--color-violet` and `--color-cyan`

**Prior: Template Color Migration (1,171 refs)**
- Bulk replacement: zinc -> text/bg hierarchy, amber -> brand, emerald -> success, red -> error, blue -> info, indigo -> interactive

**Prior: Design Token System + Theme Foundation**
- 30+ `--ichor-*` CSS custom properties, two themes (ICHOR IV dark + Swiss light)
- ~50 `ichor-*` component classes, `obs-*` -> `ichor-*` rename

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

### Remaining Hardcoded Colors
- ~35 categorical event-type colors (yellow, orange, pink, rose, teal, lime, fuchsia, purple) in `dashboard_format_helpers.ex`, `dashboard_timeline_helpers.ex`, and scattered components. These are intentional visual identifiers for ~15 event types, not candidates for semantic tokens.
- 1 `text-green-500` in `session_drilldown_live.ex` (HITL status)

### Next Steps
1. **Theme switcher UI**: Add toggle button in dashboard header
2. **Categorical color palette** (optional): Token-based event-type palette for full Swiss theme support
3. **Streams** (deferred): Convert events list to LiveView streams for render perf
4. **LiveComponents** (deferred): Isolate fleet tree, feed, inspector as stateful components

### Memories Server
- Running on port 4000 (must be running for Archon memory tools)
- Requires Docker: postgres (port 5434) + falkordb (port 6379)
- ONNX models on external drive: `/Volumes/T5/models/ONNX`
