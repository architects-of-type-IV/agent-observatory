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
  - dashboard_message_helpers.ex: message threading, search, type icons (181 lines)
  - dashboard_messaging_handlers.ex: messaging event handlers
  - dashboard_task_handlers.ex: task CRUD event handlers
  - dashboard_navigation_handlers.ex: cross-view navigation jumps
  - dashboard_agent_helpers.ex: agent detail data derivation (34 lines)
- Reusable components in observatory_components.ex (empty_state, health_warnings, model_badge, task_column, session_dot, event_type_badge, member_status_dot, message_thread)
- GenServers: TeamWatcher (disk polling), Mailbox (ETS, 151 lines), CommandQueue (file I/O, 237 lines), Notes (ETS annotations, ~120 lines)
- Plain modules: TaskManager (task JSON CRUD, 217 lines)
- Handler modules (6 total): ui, filter, navigation, task, messaging, notification
- Ash domains (6 total): Events, AgentTools, Messaging, TaskBoard, Annotations, Costs

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
- **Handler delegation pattern**: dashboard_live.ex stays under 300 by delegating handle_event clauses to domain-specific handler modules (messaging_handlers, task_handlers, navigation_handlers, ui_handlers, filter_handlers, notification_handlers)

## Sprint 3-4 Lessons (Feb 2026)
- **Agents ignore task redirections**: When delegating to teammates, be VERY explicit about WHAT to build, not just task IDs. Agents often ignore references to "see task #N" and need direct instructions
- **Rogue agents can deliver value**: Agents that ignore shutdown requests sometimes deliver useful work, though they can cause merge conflicts. Evaluate output quality before discarding
- **Default view_mode matters for UX**: Changed from :feed to :overview for better first-time experience. Users need context (stats/recent activity) before diving into raw event streams
- **Handler count scales with features**: Started with 3 handlers (messaging, task, navigation), now 6 (added ui, filter, notification). Pattern holds well at scale
- **Member struct keys vary by source**: Team members from disk use `:agent_id`, not `:session_id`. Always check dashboard_team_helpers.ex for canonical struct shape
- **Session data enrichment pattern**: Extract session metadata (model, cwd, permission_mode) in enrich_team_members by filtering events and extracting from SessionStart payload. Store in member map for template use.
- **Current tool detection**: Find PreToolUse without matching PostToolUse/PostToolUseFailure by sorting events and checking for unmatched pairs. Calculate elapsed time from PreToolUse timestamp to now.
- **Single-line handler consolidation**: Reduced dashboard_live.ex from 313 → 245 lines by consolidating simple event handlers to single-line format (e.g., `def handle_event("filter", p, s), do: {:noreply, handle_filter(p, s) |> prepare_assigns()}`). Saves ~60 lines without sacrificing readability.
- **Selection clearing pattern**: Extract common "clear all selections" logic to helper function (`clear_selections/1`) instead of repeating `assign(:selected_event, nil) |> assign(:selected_task, nil) |> assign(:selected_agent, nil)` in every selection handler.

## Sprint 5 Lessons (Feb 2026)
- **Template component extraction**: Split 1401-line dashboard_live.html.heex into 8 view-specific component modules (overview, feed, tasks, messages, agents, errors, analytics, timeline). Reduced main template by 38% (-536 lines). Each component under 200 lines with single public function.
- **HEEx template imports**: Elixir compiler cannot detect function usage in HEEx templates, leading to "unused import" warnings for helper modules. These are false positives when helpers are called from templates (e.g., session_color/1, relative_time/2). May need to suppress warnings or restructure.
- **Component module pattern**: `use Phoenix.Component` + single public attr-based function + focused imports (ObservatoryComponents, DashboardFormatHelpers, DashboardSessionHelpers, domain helpers). Keeps main template as dispatcher + chrome only.
- **Session control handlers**: Dashboard → agent communication uses dual-write pattern (CommandQueue file writes + Mailbox ETS + PubSub). Handler modules return socket (not {:noreply, socket}) to allow prepare_assigns() wrapper in dashboard_live.ex.
- **Inline editing with phx-change**: For dropdowns in task cards, use phx-change (not phx-click) with hidden phx-value-* attributes to pass context. Event handler receives params with both the select value (name="status") and the context values (phx-value-team, phx-value-task_id).
- **Browser confirmation dialogs**: Use data-confirm="Message?" attribute on buttons for simple yes/no confirmations. Browser handles the prompt - no JavaScript needed.
- **Team member data structure**: Team members from sel_team.members use :agent_id and :name keys (not :session_id). Owner dropdowns should use member[:agent_id] || member[:name] as the value.
- **QA endpoint testing**: All endpoints verified (POST /api/events, GET /export/events, GET /, POST /mcp). Check for phx-socket in HTML to verify LiveView mount. Use curl with -w for HTTP status codes.

## Component Refactoring Lessons (Feb 2026)
- **embed_templates incompatible with attr declarations**: When using `attr` + `embed_templates` together, Phoenix Component throws "could not define attributes" error. Use inline ~H instead for small components.
- **Inline ~H preferred for tiny components**: For components under 30 lines, inline ~H in .ex file is cleaner than separate .heex files. No need to split template when total size is minimal.
- **defdelegate facade preserves imports**: Replacing large component module with defdelegate facade maintains backward compatibility. Existing `import ObservatoryWeb.ObservatoryComponents` still works.
- **Helper function location matters**: session_color is in DashboardFormatHelpers (not DashboardSessionHelpers). Always grep to verify helper location before importing.

## QA Testing Patterns (Feb 2026)
- **Complete agent lifecycle**: SessionStart + PreToolUse/PostToolUse pairs + SessionEnd
- **Varying durations**: Mix fast (<100ms), medium (100-1000ms), slow (>3000ms) to test duration colors
- **curl verification**: Check LiveView mount (phx-socket), session IDs, tool names in HTML
- **Initial render vs real-time**: curl tests initial render only, browser needed for WebSocket updates

## PubSub Topics
- "events:stream" - all events
- "teams:update" - team state changes
- "agent:crashes" - agent crash notifications
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

## Agent Crash Detection (Task #13)
AgentMonitor GenServer monitors agent health and auto-reassigns tasks from crashed agents:
- Subscribes to "events:stream" PubSub topic to track agent activity
- Tracks session state: %{session_id => %{last_event_at, team_name}}
- Every 5s checks for agents idle >120s without SessionEnd
- On crash: broadcasts {:agent_crashed, session_id, team_name, reassigned_count}
- Auto-reassigns crashed agent's tasks (TaskManager.update_task sets owner -> nil)
- Writes crash notification to ~/.claude/inbox/crash_{team}_{sid}_{ts}.json
- Dashboard subscribes to "agent:crashes" and shows flash message

## Messages View Architecture (Feb 2026)
- Messages derived from SendMessage tool events
- Threads grouped by sender-recipient pairs (bidirectional)
- Thread metadata: participants, message_count, unread_count, has_urgent, message_types
- Message types: message, broadcast, shutdown_request/response, plan_approval_request/response
- Search filters by content, sender, or recipient
- Collapsible threads with state in LiveView assigns
- Icon system: 💬 (DM), 📢 (broadcast), ⚠️ (urgent), ✓ (response)

## Agent Detail Panel Pattern (Feb 2026)
- Follows event/task detail panel pattern: right sidebar, toggle selection, sticky header
- Helper module (dashboard_agent_helpers.ex) for data derivation
- Selection clears other panels (event/task)
- Displays: full session ID, model, permission mode, cwd, uptime, health metrics, recent 15 events, assigned tasks, message form, actions
- Member cards clickable with selection highlight (border change)
- Reuses existing components: member_status_color, model_badge, event_type_badge, health_warnings

## Sprint 5 Lessons (Feb 2026)
- **5 parallel agents with non-overlapping file scopes**: Assign each agent specific files to create/modify. Zero merge conflicts achieved.
- **Agents self-wire when possible**: activity-builder and task-editor wired their own event handlers into dashboard_live.ex, reducing integrator work
- **Component extraction fixes size violations**: Moving task_column from observatory_components (335 lines) to tasks_components (77 -> 144 lines) brought both under 300
- **Ash resource pattern**: Domain at lib/observatory/{domain}.ex, resource at lib/observatory/{domain}/{resource}.ex. Use `mix ash.codegen --name X` for migrations.
- **Feed grouping reuses timeline pairing**: Tool event pairing (PreToolUse + PostToolUse by tool_use_id) is same pattern as timeline_helpers
- **Agent activity summarization**: Parse hook event payload by tool_name to generate human-readable summaries (Read -> "Reading {path}", Bash -> "Running `{cmd}`")
