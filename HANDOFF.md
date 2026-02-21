# Observatory - Handoff

## Current Status: Swarm Control Center (2026-02-21)

Complete dashboard redesign adding a swarm/DAG operational cockpit with cross-protocol message tracing.

## Navigation Redesign

**Before (9 flat tabs):** Overview | Feed | Tasks | Messages | Agents | Errors | Analytics | Timeline | Teams

**After (4 primary + More dropdown):** Overview | Protocols | Feed | Errors | More...

Overview stacks Command+Pipeline+Agents in one view. The "More" dropdown contains: Command, Pipeline, Agents, Tasks, Messages, Analytics, Timeline, Teams. Default view is `:overview`. Keyboard shortcuts 1-4 map to: Overview, Protocols, Feed, Errors.

## Feed View -- Segment-Based Architecture

The feed groups events by session, then segments each session by subagent spans.

**Key finding**: SubagentStart/SubagentStop hooks fire on the PARENT session_id. Subagents get short hash IDs (e.g., "ac67b7c"), NOT separate session UUIDs. All subagent tool calls (Read, Bash, etc.) appear under the parent's session_id.

**Segment model** (`dashboard_feed_helpers.ex`):
- Each session's events are split into segments: `:parent` (direct events) and `:subagent` (events bracketed by SubagentStart/SubagentStop)
- Subagent segments include: agent_id, agent_type, start/stop events, tool pairs, event counts
- Segments render sequentially: parent events -> subagent block -> parent events -> subagent block -> ...
- Subagent blocks are collapsible (key: "sub:{agent_id}" in collapsed_sessions MapSet)
- Parallel subagents: events in overlapping time ranges appear in BOTH subagent blocks

**Visual structure**:
```
Session Block (collapsible)
  Header: agent name, role badge, session_id, model, permission, source, stats
  Start Banner (green)
  Segments:
    Parent events: tool pairs + standalone events
    Subagent Block (cyan, collapsible)
      Header: agent_type, agent_id, event/tool counts, time range
      Spawn marker
      Tool pairs + standalone events
      Reap marker
    Parent events (between subagents)
    ...
  End/Stop Banner (red)
  Active indicator (pulsing green)
```

## New Backend GenServers

### SwarmMonitor (`lib/observatory/swarm_monitor.ex`)
- Polls `tasks.jsonl` from discovered project paths every 3s
- Runs `health-check.sh` every 30s
- DAG computation: topological sort into execution waves, critical path via DFS with memoization
- Detects stale tasks (in_progress > 10 min without update) and file conflicts
- Action functions: `heal_task`, `reassign_task`, `reset_all_stale`, `trigger_gc`, `claim_task`
- Project discovery from `~/.claude/teams/*/config.json` member `cwd` fields + archives
- Broadcasts state on `"swarm:update"` PubSub topic

### ProtocolTracker (`lib/observatory/protocol_tracker.ex`)
- Subscribes to `"events:stream"` PubSub
- Creates message traces for SendMessage, TeamCreate, SubagentStart events
- Tracks multi-hop delivery: HTTP -> Mailbox ETS -> CommandQueue filesystem -> PubSub
- Maintains last 200 traces in `:protocol_traces` ETS table
- Broadcasts stats on `"protocols:update"` PubSub topic every 5s

## New View Components

### Command View (`:command` -- key 1)
Operational cockpit. File: `lib/observatory_web/components/command_components.ex`
- **Health bar**: status indicator (green/red), project selector, pipeline progress bar, action buttons
- **Agent grid**: CSS Grid of clickable cells showing name, model, current tool + elapsed time, task ID, health warnings
- **Alerts panel**: health issues + stale tasks with per-issue heal buttons
- **Selected detail**: agent info (model, status, uptime, cwd) + task info + actions (Pause/Resume/Shutdown) + message form

### Pipeline View (`:pipeline` -- key 2)
DAG visualization. File: `lib/observatory_web/components/pipeline_components.ex`
- **Project selector**: dropdown of registered projects + inline add-project form
- **DAG visualization**: tasks arranged in wave columns, critical path highlighting, status colors
- **Task table**: sortable with ID, Status, Subject, Owner, Priority, Blocked By, Updated
- Bidirectional selection: click DAG node highlights table row and vice versa

### Protocols View (`:protocols` -- key 4)
Cross-protocol tracing. File: `lib/observatory_web/components/protocol_components.ex`
- **Protocol summary**: 4 cards (HTTP, PubSub, Mailbox, CommandQueue) with current counts
- **Message flow**: chronological traces with hop visualization (colored status dots per protocol)
- **Channel detail**: per-agent mailbox stats table, per-session CommandQueue stats table

## Handler Module

`lib/observatory_web/live/dashboard_swarm_handlers.ex` handles:
`select_project`, `add_project`, `heal_task`, `reassign_swarm_task`, `reset_all_stale`, `trigger_gc`, `run_health_check`, `claim_swarm_task`, `select_dag_node`, `select_command_agent`, `clear_command_selection`, `send_command_message`

## Backend Modifications

| File | Change |
|------|--------|
| `team_watcher.ex` | `parse_members` preserves cwd, model, is_active, tmux_pane_id, color, joined_at; added `derive_project/1` |
| `mailbox.ex` | Added `get_stats/0` for per-agent message counts (total, unread, oldest_unread_age) |
| `command_queue.ex` | Added `get_queue_stats/0` for per-session pending file counts and oldest file age |
| `application.ex` | Added SwarmMonitor + ProtocolTracker to supervision tree |

## JS Changes (assets/js/app.js)

- `viewModes` array: `["overview", "protocols", "feed", "errors"]`
- Added `MoreDropdown` hook (toggle on button click, close on outside click)

## Hooks Compatibility

All 13 hook types in `~/.claude/settings.json` send events via `~/.claude/hooks/observatory/send_event.sh`. The ProtocolTracker correctly matches event atoms (`:PreToolUse`, `:SubagentStart`) from the event pipeline: hook JSON -> POST /api/events -> Ash Event (atom types) -> PubSub -> ProtocolTracker.

## Files Created (6)

| File | Lines | Purpose |
|------|-------|---------|
| `lib/observatory/swarm_monitor.ex` | ~710 | GenServer: tasks.jsonl parser, health runner, DAG, actions |
| `lib/observatory/protocol_tracker.ex` | ~230 | GenServer: cross-protocol message correlation |
| `lib/observatory_web/components/command_components.ex` | ~535 | Command Center: agent grid, health, alerts |
| `lib/observatory_web/components/pipeline_components.ex` | ~270 | DAG visualization + task table |
| `lib/observatory_web/components/protocol_components.ex` | ~270 | Message flow + channel stats |
| `lib/observatory_web/live/dashboard_swarm_handlers.ex` | ~100 | Event handlers for swarm actions |

## Files Modified (7)

| File | Change |
|------|--------|
| `lib/observatory/team_watcher.ex` | parse_members + derive_project |
| `lib/observatory/mailbox.ex` | get_stats/0 |
| `lib/observatory/command_queue.ex` | get_queue_stats/0 |
| `lib/observatory/application.ex` | SwarmMonitor + ProtocolTracker in sup tree |
| `lib/observatory_web/live/dashboard_live.ex` | subscriptions, assigns, 10+ handle_event clauses |
| `lib/observatory_web/live/dashboard_live.html.heex` | nav restructure, 3 new view blocks |
| `assets/js/app.js` | viewModes array, MoreDropdown hook |

## File Split: embed_templates Refactor

Large component files split into `.ex` (logic) + `.heex` (templates) using `embed_templates`:

| Module | Before | After | Templates Created |
|--------|--------|-------|-------------------|
| `command_components.ex` | 535 lines | 102 lines | 6 heex files in `command_components/` |
| `pipeline_components.ex` | 276 lines | 61 lines | 2 heex files in `pipeline_components/` |
| `protocol_components.ex` | 272 lines | 52 lines | 5 heex files in `protocol_components/` |
| `session_group.ex` | 388 lines | 98 lines | 3 heex files in `session_group/` |

**Pattern**: Preprocessing moves into `<% %>` blocks at top of .heex templates. Multi-head pattern-matched functions stay as manual `defp` dispatch in .ex files (e.g., `segment/1`, `role_badge/1`).

## Feed Nesting: Tool Chains

Consecutive tool calls grouped into collapsible chains with summary headers.

**New component**: `lib/observatory_web/components/feed/tool_chain.ex` + `tool_chain/tool_chain.html.heex`

**Timeline builder** (`dashboard_feed_helpers.ex`):
- `build_segment_timeline/2`: interleaves tool pairs and standalone events chronologically, groups consecutive tools into `{:tool_chain, pairs}` tuples
- `chain_tool_summary/1`: "Read x3, Edit x1, Bash x1" summary
- `chain_total_duration/1`, `chain_status/1`: aggregate stats

**Nesting structure**:
```
Session Block (collapsible)
  Parent Segment
    Tool Chain (collapsible) -- e.g. "3 tools: Read x2, Edit"
      Tool: Read (collapsible)
        START detail
        DONE detail
      Tool: Edit (collapsible)
        START detail
        DONE detail
    Standalone Event (UserPromptSubmit, etc.)
    Tool Chain ...
  Subagent Block (collapsible)
    Same nesting inside
```

**Collapse keys**: `"chain:{first_tool_use_id}"` for chain groups, `"tool:{tool_use_id}"` for individual tools.

## Navigation: Flat Tabs

All 12 views as flat tabs at equal weight. Keyboard shortcuts 1-9,0 for first 10. MoreDropdown hook removed.

## Overview: Unified Control Plane

Single purpose-built view surfacing ALL dimensions. Not a stack of other components.

**Fleet bar**: node counts, error count, message count, tool count, task pipeline progress, protocol stats (H/P/M/Q), health indicator. All updating in real-time via PubSub.

**Cluster hierarchy**: project clusters -> swarm groups -> agent rows. Scale caps (swarm: 10, standalone: 20) with overflow. Health-colored borders.

**Activity section** (below clusters):
- Errors: red-bordered card with top 3 recent errors (tool name + project)
- Messages: recent 5 messages with from->to and content preview
- Alerts: swarm health issues + stale tasks with heal buttons

**Detail panel**: right side, shows on agent/task click. Message form shows "To: {name} ({id})" with toast feedback on send.

**Data flow**: command_view receives @errors, @messages, @protocol_stats, @active_tasks from LiveView. No separate pipeline/agents stacked below.

## Collapsible Sidebar

Toggle button (< / >) at left edge. State persisted in localStorage via StatePersistence hook. Sidebar width transitions from w-72 to w-0.

## SwarmMonitor: Auto Re-Discovery

`poll_tasks` now calls `discover_projects()` on every 3s cycle, merging new teams automatically. No restart needed when a new swarm starts.

## Swarm Readiness (memories project)

- SwarmMonitor active: memories project discovered from archived team configs
- tasks.jsonl: 8 tasks, 6 DAG waves, all pending
- Pipeline view: project selector, DAG visualization, task table all wired
- Global hooks: all 13 types fire `send_event.sh` -> Observatory POST /api/events
- Worker tmux sessions will auto-register as nodes in Command view via SessionStart events

## Build Status

`mix compile --warnings-as-errors` -- PASSES (zero warnings)

## Previous Work

### Message Forms Unified (2026-02-15)
All 4 dashboard-to-agent message forms unified to use Mailbox delivery. Forms protected with `phx-update="ignore"` + `ClearFormOnSubmit` JS hook.

### Team Inspector (2026-02-15)
17/17 tasks complete. Inspector drawer with 3-state sizing, tmux view overlay, hierarchical message targeting.
