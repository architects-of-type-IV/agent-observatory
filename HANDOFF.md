# Observatory - Handoff Document

## Current State
The Observatory multi-agent observability dashboard is functional with these completed features:

### Completed Tasks
- #1: Codebase audit
- #2: Extract inline HEEx template to dashboard_live.html.heex
- #3: Extract helper functions to dashboard_helpers.ex (503 lines -> now split)
- #4: Extract reusable function components to observatory_components.ex
- #5: Verify compilation (zero warnings confirmed)
- #8: Design clickable task board (architecture)
- #9: Design team split view (architecture)
- #14: Implement clickable task detail panel + team split view + agent panels
- #22: Split dashboard_helpers.ex into 3 modules under 300 lines each

### Pending Tasks
- #10, #11, #15: Superseded by #14
- #19: PubSub channel system for bidirectional agent messaging (blocked by #14, now unblocked)

### Architecture
- Elixir 1.19 / Phoenix 1.8.3 / Ash 3.x / SQLite
- Hook scripts POST events to /api/events
- Events broadcast via PubSub to LiveView dashboard
- TeamWatcher GenServer polls ~/.claude/teams/ and ~/.claude/tasks/ every 2s
- Teams derived from both events AND disk state

### Key Files
| File | Lines | Purpose |
|------|-------|---------|
| dashboard_live.ex | 218 | LiveView mount + event handlers + prepare_assigns |
| dashboard_live.html.heex | ~589 | Template with 4 view modes |
| dashboard_team_helpers.ex | 148 | Team derivation, member enrichment, status colors |
| dashboard_data_helpers.ex | 222 | Task/message derivation, filtering, search |
| dashboard_format_helpers.ex | 192 | Display formatting, event summaries, colors |
| observatory_components.ex | 127 | Reusable function components |
| team_watcher.ex | ~143 | Disk-based team state polling |
| event_controller.ex | API endpoint for hook events |
| application.ex | Supervision tree with TeamWatcher |

### View Modes
1. **Feed**: Real-time event stream with filters and search
2. **Tasks**: Kanban board (Pending/In Progress/Completed) - clickable with detail panel
3. **Messages**: Team message thread view
4. **Agents**: 2-column grid of team panels with member status and task progress

### Next Priority
Task #19: PubSub channel system for bidirectional agent messaging
- Channel topology: agent:{session_id}, team:{team_name}, dashboard:commands
- Mailbox pattern with read/unread state
- UI controls to send messages, push context, reassign tasks

### User Constraints
- All modules must be under 200-300 lines
- Zero warnings policy (mix compile --warnings-as-errors)
- Always run builds after changes
- Do NOT use rm - move to tmp/trash/
- Do NOT cd into subdirectories
- Read existing code before modifying
