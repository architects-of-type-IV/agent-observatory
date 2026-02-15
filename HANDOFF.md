# Observatory - Handoff

## Current Status: MCP Messaging Pipeline Verified Working

## What Happened This Session

Tested `/orchestrate` on a real task: verify the Mailbox MCP server works end-to-end for dashboard-to-agent messaging. Used FIX-LOOP workflow.

### FIX-LOOP Results

**REPRODUCE**: Tested all 5 MCP tools via curl and direct MCP tool calls.

**DIAGNOSE**: Traced full messaging pipeline:
- Dashboard -> Agent: LiveView form -> `Mailbox.send_message/4` -> ETS + CommandQueue (filesystem)
- Agent -> Dashboard: MCP `send_message` -> Mailbox -> ETS + PubSub broadcast
- Agent inbox: MCP `check_inbox` -> Mailbox -> ETS lookup
- Agent ack: MCP `acknowledge_message` -> Mailbox -> mark read
- Task ops: MCP `get_tasks` / `update_task_status` -> TaskManager

**VERIFY**: All 5 MCP tools work correctly:
- `send_message` -- delivers to ETS + writes `~/.claude/inbox/{session_id}/{id}.json`
- `check_inbox` -- returns unread messages from ETS
- `acknowledge_message` -- marks as read
- `get_tasks` -- returns tasks (empty when none assigned)
- `update_task_status` -- updates task status

### Findings

1. **Not a bug**: Earlier curl test failure was zsh history expansion mangling `!` in shell. Using file input (`-d @file.json`) or MCP tools directly works fine.
2. **AshAi argument nesting**: AshAi expects tool arguments under `"input"` key: `{"arguments": {"input": {"from_session_id": ...}}}`. This is handled automatically by MCP clients.
3. **Unused Ash resource**: `Observatory.Messaging.Message` is defined but never used. Messages only live in ETS (lost on restart) and filesystem. Future consideration.
4. **Server runs on port 4005** (not 4000).

## No Code Changes
The observatory repo has no uncommitted changes. The messaging pipeline was already correctly implemented.

## Team Inspector Scout - 2026-02-15
### Data Structure Analysis (READ-ONLY)

Completed analysis of all team-related data structures for team-inspector project:

**Key data flows identified:**
- TeamWatcher polls `~/.claude/teams/` and `~/.claude/tasks/` every 2s
- Teams come from two sources: disk (TeamWatcher) and events (hook events)
- DashboardTeamHelpers merges both sources, disk is authoritative
- Members enriched with health, status, model, cwd, current_tool, uptime from events
- PubSub topics: `teams:update`, `team:{name}`, `agent:{id}`, `session:{id}`, `events:stream`, `agent:crashes`

**Gaps for team inspector:**
- No team-level aggregate health/progress metrics
- No task completion percentage per team
- No message volume/flow tracking between members
- No team timeline (when created, duration, phases)
- No roadmap integration (`.claude/roadmaps/` not read by TeamWatcher)

## UI Component Patterns (scout-ui, 2026-02-15)

READ-ONLY analysis of all UI components, layout, and interaction patterns.

**Key findings:**
- Three-panel layout: sidebar (w-72) + main (flex-1) + conditional detail (w-96)
- Dark theme: zinc-950 base, zinc-900 cards, zinc-800 inputs/borders
- Accent colors: indigo (primary), cyan (team), emerald (success), blue (progress), amber (warning), red (error)
- Detail panel is conditional render (no animation/drawer)
- No bottom drawer or slide-up panel exists anywhere -- would be new pattern
- 8 view modes switched via header tab bar, persisted to localStorage
- 6 JS hooks: StatePersistence, Toast, CopyToClipboard, BrowserNotifications, KeyboardShortcuts, ExportDropdown
- Modal pattern: fixed overlay + centered card with phx-click="stop" propagation block
- Form inputs: consistent bg-zinc-800 border-zinc-700 focus:border-indigo-500 pattern

## Team Inspector Roadmap Created - 2026-02-15

### Architecture Decisions Locked
1. **Navigation**: New view mode `:teams` (not separate route) -- follows existing 9-view pattern
2. **Live output**: Event stream via PubSub (not polling) -- reuses existing event pipeline
3. **Empty inspector**: Collapsed bar with hint text -- non-intrusive, discoverable

### Roadmap Structure
29 flat files at `.claude/roadmaps/roadmap-1771113081/` using dotted naming convention:
- Phase 1 (1-scout.md): COMPLETE -- 4 scouts analyzed views, data, messaging, UI
- Phase 2 (2-build-team-inspector.md): Implementation phase
  - Section 2.1: Backend foundations (SEQUENTIAL, team lead first)
    - 2.1.1: Team data enrichment helpers (role detection, aggregate metrics)
    - 2.1.2: Team inspector event handlers module
  - Section 2.2: Teams view components (PARALLEL Agent A)
    - 2.2.1: Teams page with team rows
  - Section 2.3: Inspector components (PARALLEL Agent B + C)
    - 2.3.1: Inspector drawer (bottom slide-out, stack, layout modes)
    - 2.3.2: Tmux view (maximized tiled output, 6 output modes)
  - Section 2.4: Messaging + integration (PARALLEL Agent D + sequential wiring)
    - 2.4.1: Message composer (multi-target messaging)
    - 2.4.2: Inspector handlers
    - 2.4.3: Dashboard integration wiring (LAST -- imports, assigns, template, keyboard shortcut 9)

### Team Status
- Team "team-inspector" created via TeamCreate
- All 4 scout agents shut down after completing Phase 1
- Implementation agents NOT YET spawned
- Scout report consolidated at `.claude/roadmaps/roadmap-1771113081/scout-report.md`

## Scout Enrichment Complete - 2026-02-15

Three scouts analyzed the codebase and enriched all roadmap tasks with:
- Exact line numbers for insertion points
- Existing function signatures and patterns to follow
- Data structure field names and edge cases
- Dependency ordering between tasks

Key scout findings:
- **Backend**: detect_role must come first (2.1.2.2 depends on it). broadcast_to_many is independent.
- **UI**: agents_components.ex is best template for teams_components.ex. No bottom drawer exists -- entirely new pattern. CSS file is app.css with Tailwind v4.
- **Integration**: 9 new handle_event clauses, 7 new mount assigns, keyboard shortcut is just array+bound change.

Architect validation pending -- will review and propose changes to roadmap.

## Next Steps
- Architect validates plan and proposes changes
- Apply architect recommendations to roadmap files
- Execute Phase 2 implementation
