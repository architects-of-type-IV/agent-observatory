# Observatory - Brain

## Architecture
- Event-driven: hooks -> POST /api/events -> Ash.create + PubSub.broadcast -> LiveView
- Dual data sources: event-derived state + disk-based team/task state (TeamWatcher)
- prepare_assigns/1 called from mount and every handle_event/handle_info

## Patterns
- Module size limit: 200-300 lines max
- Template in separate .html.heex file, not inline ~H
- Helper functions split by domain:
  - dashboard_team_helpers.ex: team derivation, member enrichment
  - dashboard_data_helpers.ex: task/message derivation, filtering
  - dashboard_format_helpers.ex: display formatting, event summaries, duration colors
  - dashboard_timeline_helpers.ex: timeline computation, block positioning
  - dashboard_session_helpers.ex: session metadata (model extraction, cwd abbreviation)
  - dashboard_messaging_handlers.ex: messaging event handlers
  - dashboard_task_handlers.ex: task CRUD event handlers
  - dashboard_navigation_handlers.ex: cross-view navigation jumps
- Reusable components in observatory_components.ex (empty_state, health_warnings, model_badge, task_column, session_dot, event_type_badge, member_status_dot)
- GenServers: TeamWatcher (disk polling), Mailbox (ETS, 151 lines), CommandQueue (file I/O, 237 lines)
- Plain modules: TaskManager (task JSON CRUD, 217 lines)

## Timeline View Implementation

### Event Pairing Strategy
Tool executions split into PreToolUse and PostToolUse with matching tool_use_id.

**Algorithm**:
1. Create Map lookup of PostToolUse events keyed by tool_use_id
2. Filter for PreToolUse events
3. For each Pre event, lookup matching Post by tool_use_id
4. Create block: start_time (Pre), end_time (Post), duration_ms (Post)

### CSS Percentage Positioning
Calculate timeline block positions as percentages of total timespan:

```elixir
start_offset_ms = DateTime.diff(block.start_time, global_start, :millisecond)
duration_ms = DateTime.diff(block.end_time, block.start_time, :millisecond)
total_duration_ms = DateTime.diff(global_end, global_start, :millisecond)

left_pct = (start_offset_ms / total_duration_ms) * 100
width_pct = max((duration_ms / total_duration_ms) * 100, 0.5)  # min 0.5% visibility
```

**Benefits**: Responsive, no JavaScript, works with Tailwind

### Idle Gap Computation
Fill gaps between tool blocks with "idle" blocks:
1. Sort tool blocks by start_time
2. Add initial idle if session_start < first_block.start_time
3. For each consecutive pair, add idle if gap exists
4. Add final idle if last_block.end_time < session_end
5. Reverse list (built backwards for performance)

### Auto-scroll UX Pattern
```javascript
AutoScrollTimeline: {
  mounted() { this.scrollToBottom() },
  updated() {
    const isNearBottom = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 100
    if (isNearBottom) { this.scrollToBottom() }
  }
}
```

Auto-scrolls on mount + updates (only if user is near bottom < 100px)

## Tool Color Mapping
Consistent colors across views:
- Bash: amber (shell)
- Read: blue (reading)
- Write: emerald (creating)
- Edit: violet (modifying)
- Grep/Glob: cyan/teal (searching)
- Task: indigo (delegation)
- Web tools: orange (external)
- Messaging: fuchsia/pink (coordination)

## Refactoring Lessons
- Extract template FIRST (biggest win), then helpers, then components
- prepare_assigns/1 pattern: single function computes all derived state
- LiveView module for lifecycle only: mount, handle_info, handle_event, prepare_assigns

## Team Coordination Lessons
- **Parallel editing creates merge conflicts**: Assign non-overlapping file scopes to parallel agents working on shared modules
- **Always do integration review**: After parallel work, review merge conflicts and integration points - views can get lost during parallel editing
- **Verify agent capabilities**: Teammates spawned in delegate mode often lack Read/Bash tools - verify before assigning file-based work
- **Shutdown enforcement**: Shutdown requests may be ignored by rogue agents - need stronger enforcement mechanism. Rogue agents can duplicate work but sometimes deliver useful results.
- **keep-track and delegate mode**: keep-track hook blocks TaskUpdate completion in delegate mode - use TaskUpdate with status=deleted instead
- **Timeline CSS absolute positioning**: left/width percentages must be on the absolutely positioned element itself, not on an inner child div
- **Overflow containment**: overflow-hidden on relative containers prevents absolute children from escaping bounds - critical for timeline swimlanes

## Sprint 2 Lessons (Feb 2026)
- **Non-overlapping file scopes prevent conflicts**: Creating NEW files (task_handlers, navigation_handlers, session_helpers) instead of editing shared dashboard_live.ex eliminated merge conflicts
- **Create new files for new features**: Better to have focused 71-180 line modules than bloat existing files past 300 lines
- **Handler delegation pattern**: dashboard_live.ex stays under 300 by delegating handle_event clauses to domain-specific handler modules (messaging_handlers, task_handlers, navigation_handlers, ui_handlers)

## PubSub Topics
- "events:stream" - all events
- "teams:update" - team state changes
- "agent:{session_id}" - per-agent mailbox
- "team:{team_name}" - team broadcast
- "session:{session_id}" - session events (including command_responses)
- "dashboard:commands" - UI -> agents

## File-Based Command Queue
CommandQueue GenServer provides dual-channel agent communication:
- **Inbox**: write_command(session_id, command) -> ~/.claude/inbox/{session_id}/{id}.json
- **Outbox**: poll_responses(session_id) reads ~/.claude/outbox/{session_id}/*.json
- Polls every 2s, broadcasts {:command_responses, []} to "session:{id}" topic
- Mailbox.send_message automatically writes to CommandQueue (dual-write pattern)

## Cross-View Navigation Pattern
Navigation handlers delegate to separate module to keep dashboard_live.ex manageable:
- Single handle_event clause with guard: `when e in ["jump_to_timeline", ...]`
- Delegates to DashboardNavigationHandlers.handle_event/3
- Returns socket (not {:noreply, socket}) - wrapper adds prepare_assigns
- Pattern: `ObservatoryWeb.DashboardNavigationHandlers.handle_event(e, p, s) |> then(&{:noreply, prepare_assigns(&1)})`
