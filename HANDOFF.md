# ICHOR IV - Handoff

## Current Status: TERMINAL PANEL IMPLEMENTED (2026-03-21)

~41 commits. Architecture complete. Audits complete. Tests passing. UI upgraded. Terminal panel live.

### Latest: Terminal Panel (UI-TMUX-PANEL)

Implemented VS Code-style terminal panel overlay replacing the old tmux modal dialog.

**New files:**
- `assets/js/hooks/terminal_panel_hook.js` -- JS hook (resize drag, localStorage persistence, layout)
- `lib/ichor_web/components/terminal_panel_components.ex` -- Phoenix component (panel UI, tabs, controls)

**Modified files:**
- `dashboard_state.ex` -- panel_visible, panel_position, panel_size, show_session_picker assigns
- `dashboard_tmux_handlers.ex` -- 7 new event handlers + disconnect_tmux_tab
- `dashboard_live.ex` -- registered new tmux events
- `dashboard_live.html.heex` -- replaced old modal with terminal_panel component
- `app.js` -- registered TerminalPanel hook + T-key shortcut

**Features:** T-key toggle, 5 positions (bottom/top/left/right/floating), 5 sizes (25-100%), session tabs with close, session picker dropdown, drag resize, localStorage persistence, minimize vs close, xterm.js with full ANSI color.

### Build
- `mix compile --warnings-as-errors`: CLEAN
- `mix assets.build`: CLEAN (929.5kb JS, 6.0kb CSS)

### Remaining (tracked in tasks.jsonl)
**Structural (medium):**
- SF-7: EventStream ETS concurrent writes (needs :protected tables)
- SF-8: Runner crash window (needs atomic Pipeline.complete + run_complete)
- ANTI-5: Blocking I/O in GenServer callbacks
- DB-1: 9 orphaned database tables
- DB-2: Snapshot-schema verification

**UI (next implementation):**
- UI-WS-PROMPTS: Add prompt CRUD to workshop

**Features:**
- PulseMonitor (tasks 1.x-4.x)
- Swarm Memory (tasks 72-77)
- Idle vs zombie UI distinction (57)

### Protocols
- Architecture docs authoritative (CLAUDE.md)
- Agents invoke ash-thinking before Ash work
- Agent prompts include WHY not just WHAT
- No mocks. Real DB. Ecto sandbox.
- Use generators whenever possible
- Read the manual before implementing
- Codex in codex-spar tmux (resume --last if exits)
