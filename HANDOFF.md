# ICHOR IV (formerly Observatory) - Handoff

## Current Status: Design Token System + Theme Foundation (2026-03-09)

### Just Completed

**Design Token System (CSS Custom Properties)**
- Added `--ichor-*` CSS custom property system to `assets/css/app.css`
- 25 design tokens covering: text hierarchy (4), backgrounds (4), borders (2), brand accent (4), semantic status (4), interactive (2), geometry/radius (5)
- Two theme definitions: ICHOR IV (dark/amber, default `:root`) and Swiss International Style (`[data-theme="swiss"]`)
- Swiss theme: pure white bg, black borders, zero border radius, Swiss Red accent -- matches Genesis project
- Theme switching via `data-theme` attribute on `<html>` (already wired in root layout)
- Body element uses `hsl(var(--ichor-bg))` and `hsl(var(--ichor-text-high))` for base colors

**Design System Rename: obs-* -> ichor-***
- All `.obs-*` CSS classes renamed to `.ichor-*` across CSS + 13 template/component files
- All `--obs-*` CSS variables renamed to `--ichor-*`
- Keyframe animation `obs-pulse` renamed to `ichor-pulse`
- tmux session prefix `obs-` intentionally NOT renamed (infrastructure, not UI)

**obs-* Design System Migrated to Tokens**
- ~50 component classes (section, card, badge, dot, button, input, etc.) now use `hsl(var(--ichor-*))` instead of hardcoded zinc/amber/emerald
- Border radius uses `var(--ichor-radius-*)` -- resolves to rounded in ICHOR IV, zero in Swiss
- All status colors (success, error, info, brand) use semantic tokens

### In Progress

**Template Migration (64 files, ~1,172 hardcoded color references)**
- The `ichor-*` design system classes are token-based, but inline Tailwind classes in templates still use hardcoded `zinc-800`, `amber-500`, etc.
- These need systematic replacement: `zinc-800` -> token, `zinc-500` -> token, `amber-*` -> brand token
- Can be done incrementally per component group

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
1. **Template color migration**: Replace ~1,172 hardcoded Tailwind color classes with semantic tokens across 64 files
2. **Archon CSS tokenization**: Convert archon-* classes from hardcoded rgba() to `hsl(var(--ichor-*))`
3. **Workshop canvas tokenization**: Convert agent-node hardcoded hex colors to tokens
4. **Theme switcher UI**: Add toggle button in dashboard header
5. **Streams** (deferred): Convert events list to LiveView streams for render perf
6. **LiveComponents** (deferred): Isolate fleet tree, feed, inspector as stateful components

### Memories Server
- Running on port 4000 (must be running for Archon memory tools)
- Requires Docker: postgres (port 5434) + falkordb (port 6379)
- ONNX models on external drive: `/Volumes/T5/models/ONNX`
