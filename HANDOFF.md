# Observatory - Handoff Document

## Current State
The Observatory multi-agent observability dashboard is fully functional with 7 view modes, PubSub messaging, agent health monitoring, and comprehensive analytics.

### Completed Tasks
- #1-5: Core refactoring (audit, template extraction, helpers, components, verification)
- #8-9, #14: Task board + team split view + agent panels
- #19: PubSub channel system for bidirectional messaging
- #22: Split dashboard_helpers into 3 focused modules
- #28: Timeline/Swimlane View
- **Session 4 Complete**: All 7 view modes operational, error dashboard, analytics leaderboard, keyboard shortcuts, agent health monitoring
- **Checkpoint (231b08b -> 18655b9)**: Integration review resolved parallel editing conflicts, all views verified working
- **Task #7 Complete**: File-based command queue (CommandQueue GenServer)
- **Task #8 Complete**: Task mutation from UI (TaskManager + CRUD handlers + create modal)
- **Task #13 Complete**: Crash detection and auto-task-reassignment (AgentMonitor)

### System Features

#### PubSub Messaging
- Mailbox GenServer with ETS-backed message queues
- CommandQueue GenServer for file-based agent communication (inbox/outbox)
- Channels module for bidirectional messaging
- Topics: agent:{id}, team:{name}, session:{id}, events:stream, teams:update

#### Agent Health Monitoring
- Red/Amber/Green health dots based on error frequency
- Computed in dashboard_agent_health_helpers.ex
- Visual indicators in agent panels

#### Error Dashboard
- Error grouping and filtering
- Unacked error badges
- Error detail panels with context

#### Analytics Dashboard
- Tool performance leaderboard (total calls, total duration, avg duration)
- Slowest individual tool calls
- Tool-specific breakdowns

#### Timeline View
- Horizontal swimlane visualization per session
- Pure CSS percentage-based positioning
- Tool pairing: PreToolUse + PostToolUse matched by tool_use_id
- Idle gaps showing thinking/processing time
- Interactive: click blocks for detail panel
- Auto-scroll following latest activity

#### Keyboard Shortcuts
- `?` - Help/shortcuts overlay
- `f` - Toggle filter panel
- `1-8` - Switch view modes (Overview, Feed, Tasks, Messages, Agents, Errors, Analytics, Timeline)
- `Esc` - Clear selection/close modals
- `j/k` - Navigate events (vim-style)
- `Enter` - Select highlighted event

### View Modes (8 total)
1. **Overview**: Default landing page with stat cards + recent activity (keyboard: 1) ← DEFAULT
2. **Feed**: Real-time event stream (keyboard: 2)
3. **Tasks**: Kanban board (keyboard: 3)
4. **Messages**: Team messaging (keyboard: 4)
5. **Agents**: Team grid panels (keyboard: 5)
6. **Errors**: Error grouping (keyboard: 6)
7. **Analytics**: Tool performance (keyboard: 7)
8. **Timeline**: Swimlane visualization (keyboard: 8)

### Key Files
| File | Lines | Purpose |
|------|-------|---------|
| dashboard_live.ex | 297 | LiveView + prepare_assigns |
| dashboard_live.html.heex | ~841 | Template with 7 view modes |
| dashboard_team_helpers.ex | 160 | Team derivation |
| dashboard_data_helpers.ex | 299 | Task/message derivation |
| dashboard_format_helpers.ex | 199 | Display formatting |
| dashboard_timeline_helpers.ex | 261 | Timeline computation |
| dashboard_agent_health_helpers.ex | 137 | Agent health monitoring |
| dashboard_messaging_handlers.ex | 94 | Messaging handlers |
| observatory_components.ex | 127 | Reusable components |
| mailbox.ex | 151 | ETS-backed message queues |
| command_queue.ex | 237 | File-based command queue |
| task_manager.ex | 217 | Task CRUD for JSON files |
| dashboard_task_handlers.ex | 180 | Task mutation event handlers |
| dashboard_ui_handlers.ex | 41 | Modal toggles |
| dashboard_navigation_handlers.ex | 71 | Cross-view navigation |
| dashboard_filter_handlers.ex | ~85 | Filter/preset management |
| dashboard_notification_handlers.ex | ~95 | Toast/browser notifications |
| channels.ex | 160 | PubSub channel management |
| agent_monitor.ex | 170 | Crash detection & task reassignment |
| notes.ex | ~120 | ETS-backed event annotations |

### Compilation Status
✅ `mix compile --warnings-as-errors` SUCCESS (zero warnings)

### Latest Update (2026-02-14 - Sprint 3 Complete + Sprint 4 In Progress)

**Sprint 3 Complete**: Overview dashboard, localStorage persistence, crash detection, toast/browser notifications

**Sprint 4 In Progress**: Export (JSON/CSV), filter presets, message threading, event annotations

**Completed Features**:
- **Overview Dashboard** (DEFAULT landing page)
  - Stat cards: teams, agents, tasks, errors, active sessions
  - Recent activity feed with last 10 events
  - Better first-time UX vs jumping straight to event feed

- **localStorage Persistence**
  - View mode, filters, search query persist across page reloads
  - User preferences maintained in browser storage

- **Toast + Browser Notifications**
  - Flash messages for crashes, task updates, system events
  - Browser notifications (with permission) for critical alerts
  - dashboard_notification_handlers.ex delegates notification logic

- **Handler Delegation Pattern**
  - dashboard_live.ex stays under 300 lines
  - 6 handler modules: ui, filter, navigation, task, messaging, notification
  - Clean separation of concerns by domain
- **Cross-View Navigation** (7 jump types between all views)
  - Errors → Timeline/Feed, Tasks → Agents, Messages → Feed
  - Timeline blocks → Feed (event selection)
  - Agents → Tasks (filter by agent), Analytics → Feed (filter by tool)

- **File-Based Command Queue** (agent communication bridge)
  - CommandQueue GenServer writes to ~/.claude/inbox/, polls ~/.claude/outbox/
  - Dual-write pattern: ETS + file system for agent coordination

- **Task CRUD from UI**
  - TaskManager module for JSON file operations
  - Create task modal with subject/description/owner
  - Backend ready for inline edit/delete/reassign

- **Hidden Data Surfaced**
  - Agent health warnings (Red/Amber/Green with details)
  - Model badges (opus/sonnet/haiku) on session cards
  - Current working directory (abbreviated) on session cards
  - Duration colors on ALL events (gray <1s, amber 1-5s, red >5s)

- **Visual Polish**
  - Empty states for all 7 views (reusable component)
  - Pulsing error badges for prominence
  - Timeline legend + tool names on wide blocks
  - Idle agents at 60% opacity
  - Shortcuts help button in header

**New Modules Created**:
- command_queue.ex (237 lines) - File-based agent communication
- task_manager.ex (217 lines) - Task JSON CRUD operations
- dashboard_task_handlers.ex (180 lines) - Task mutation event handlers
- dashboard_navigation_handlers.ex (71 lines) - Cross-view navigation jumps
- dashboard_session_helpers.ex (71 lines) - Model/cwd extraction utilities
- dashboard_ui_handlers.ex (41 lines) - Modal toggles
- agent_monitor.ex (170 lines) - Agent crash detection & task reassignment

**Module Size Status**:
All modules under 300 lines. dashboard_live.ex kept at 303 by delegating to handler modules.

### Sprint 3: Overview + Persistence + Notifications (COMPLETE)

**Completed**:
- **Task #13**: Crash detection and auto-task-reassignment
  - AgentMonitor GenServer tracks agent activity (120s timeout)
  - Auto-reassigns tasks from crashed agents (owner -> nil)
  - Writes crash notifications to ~/.claude/inbox/crash_{team}_{sid}_{ts}.json
  - Dashboard shows flash messages with crash details
- **Overview dashboard** - DEFAULT view mode with stat cards + recent activity
- **localStorage persistence** - View mode, filters, search persist across reloads
- **Toast + browser notifications** - Flash messages + critical alerts
- **Handler delegation** - 6 handler modules keep dashboard_live.ex under 300 lines

### Sprint 4: Export + Threading + Annotations (IN PROGRESS)

**In Progress**:
- Export functionality (JSON/CSV for events, tasks, analytics)
- Filter presets (save/load/share common filter combinations)
- Message threading (group related agent messages in conversation view)
- Event annotations (add notes to specific events via Notes GenServer)

**Remaining**:
- Session control (pause/resume/kill agents)
- Failure recovery and restart mechanisms
- Deeper orchestration (spawn/message/coordinate from UI)
- Dependency graph visualization
- Cost tracking and budgets
- Session replay functionality

### User Constraints
- All modules under 200-300 lines
- Zero warnings policy
- Always run builds after changes
- No rm - move to tmp/trash/
- No cd into subdirectories
