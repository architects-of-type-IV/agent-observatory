# Observatory

Real-time multi-agent observability dashboard for Claude Code. Hooks into Claude Code's lifecycle events to capture, stream, and visualize all agent activity in a Phoenix LiveView dashboard.

## Stack

Elixir 1.19 / Phoenix 1.8 / Ash 3.x / AshAi / SQLite / LiveView

## Quick Start

```bash
mix setup
mix phx.server
```

Dashboard at [localhost:4005](http://localhost:4005).

## Architecture

```
Claude Code Agents
  -> Shell hook scripts (read stdin JSON, curl POST)
    -> Phoenix API (POST /api/events)
      -> Ash.create + PubSub.broadcast
        -> LiveView Dashboard (real-time updates)

Claude Code Agents
  -> MCP client (http://localhost:4005/mcp)
    -> AshAi MCP Server
      -> check_inbox, send_message, get_tasks, etc.
```

## Views

### 1. Overview (default)

The landing page. Gives a high-level snapshot of system state.

**See:**
- 6 metric cards in a responsive grid: Active Teams (with total agent count), Tasks (with progress bar), Messages, Events (visible + cached), Errors (red when > 0), Sessions
- Recent Activity feed showing last 10 events with color-coded session dots, relative timestamps, tool names, and summaries

**Do:**
- Click "View -->" on any card to jump to its dedicated view
- Click "View all -->" to open the full event feed
- Hover cards for visual feedback

### 2. Feed

Real-time event stream with two display modes.

**See:**
- Toggle between Chronological (flat list) and Group by Agent modes
- Chronological: every event with session color dot, relative timestamp, event type badge, tool name (cyan for team tools), summary, duration with color coding, note indicator
- Grouped: collapsible session groups with model badge, event count, working directory; green session-start and red session-end banners; paired tool execution blocks (START/DONE/FAIL) with elapsed time; standalone events
- Filter presets: Failed Tools, Team Events, Slow (>5s), Errors Only
- Detail panel (right sidebar) with full event metadata, raw JSON payload, and notes

**Do:**
- Toggle chronological/grouped view
- Click any event to open detail panel
- Search events by text (tool, command, file, message, team)
- Filter by source app, event type, or presets
- Add/delete notes on events
- Copy event payload to clipboard
- Filter by session, tool, or related events from detail panel
- Export filtered events as JSON or CSV

### 3. Tasks

Kanban board for team task management.

**See:**
- Three columns: Pending (gray), In Progress (blue, pulsing dot), Completed (emerald, strikethrough)
- Task cards with ID, subject, status dropdown, owner dropdown, delete button
- Blocked-by indicators on pending tasks, active form text on in-progress tasks
- Task count per column
- Detail panel with full description, metadata, blocked-by/blocks lists

**Do:**
- Create new tasks via "+ New Task" modal (subject, description, owner)
- Change task status inline via dropdown
- Reassign task owner inline via dropdown
- Delete tasks with confirmation prompt
- Click task subject to open detail panel
- Navigate to agent view or filter feed from detail panel

### 4. Messages

Inter-agent message threads.

**See:**
- Threads grouped by conversation pair (bidirectional)
- Thread header: participants, message count, unread badge, type icons, last message time
- Message types with color-coded borders: regular (gray), broadcast (amber), shutdown request (red), shutdown response (emerald), plan approval (blue)
- Type icons per message (DM, broadcast, urgent, response)
- Urgent indicator (pulsing) for shutdown/plan approval requests
- Individual messages: sender dot, sender ID, recipient, timestamp, content

**Do:**
- Search messages by content, sender, or recipient
- Expand/collapse individual threads
- Expand All / Collapse All buttons
- Scroll within threads (max height with overflow)

### 5. Agents

Team grid with deep agent inspection.

**See:**
- Team cards in 2-column grid with name, description, task progress bar, broadcast input
- Member cards: status dot (green/amber/gray), name, type, model badge, permission mode badge, task count badge, unread message badge, working directory, uptime, event count, current running tool with elapsed time, failure rate (color-coded), health warnings
- Idle agents at 60% opacity, selected agent with indigo highlight
- Detail panel (right sidebar): full session ID, model, permission mode, cwd, uptime, event count, assigned tasks, health metrics, activity stream (last 15 events with expandable payloads), message form, action buttons

**Do:**
- Click member card to select agent and open detail panel
- Send direct message to any agent
- Send broadcast to entire team
- Click task count badge to filter tasks by agent
- Click "Events" to filter feed to agent's events
- Expand/collapse event payloads in activity stream
- Click "Focus" for full-screen agent inspection (Agent Focus view)
- Pause, resume, or shutdown agents from detail panel
- Filter to session or view feed from detail panel

### Agent Focus (full-screen)

**See:**
- Left: unlimited scrollable activity stream with timestamps, summaries, expandable payloads
- Right sidebar: agent info (name, type, model, status, cwd, uptime, events), assigned tasks, health issues

**Do:**
- Scroll through full event history
- Expand/collapse any event to inspect payload
- Click "Back" to return to agents view

### 6. Errors

Grouped error dashboard.

**See:**
- Errors grouped by tool name in red-themed cards
- Error count badge with pulsing animation per group
- Latest error timestamp per group
- Individual errors: session color dot, short session ID, timestamp, error message (up to 5 per group with overflow count)
- Error count badge in header nav (visible from all views)

**Do:**
- Click "View in Timeline" to jump to error's session in timeline
- Click "View in Feed" to jump to error's session in feed

### 7. Analytics

Tool performance metrics.

**See:**
- Table with columns: tool name, total uses, successes, failures, failure rate, average duration
- Failure rates above 30% highlighted in red
- Sorted by most-used tools first

**Do:**
- Click any tool row to filter feed to that tool's events

### 8. Timeline

Horizontal swimlane visualization of tool executions.

**See:**
- Color legend: blue (Bash), emerald (Read/Write/Edit), amber (Search), purple (Task/Team), gray (idle)
- One swimlane per session with session dot, source app, session ID, total duration
- Tool execution blocks positioned by time with tool name labels on wide blocks
- Idle gaps between tool blocks shown in gray
- Time axis with relative offsets (+0s, +Xm, +Xh)
- Tooltips on hover with tool name and summary

**Do:**
- Click any tool block to select and inspect in detail panel

### Global Features

**Header (always visible):**
- View mode tabs with badge counters (task progress, message count, error count)
- Live indicator (animated green pulse)
- Event counter (visible/total)
- Export dropdown (JSON, CSV)
- Clear events button
- Keyboard shortcuts help button (?)

**Left Sidebar:**
- Team cards with member list, task progress bars, status indicators
- Standalone sessions list with search, model badges, event counts, durations

**Right Detail Panel (contextual):**
- Event detail: metadata grid, action buttons, notes, raw payload
- Task detail: description, blocked-by/blocks, actions
- Agent detail: metadata, health, activity stream, message form, actions

**Keyboard Shortcuts:**
- `1-8`: Switch views
- `f`: Focus search
- `j/k`: Navigate events
- `Esc`: Clear selection
- `?`: Show help

**Cross-View Navigation:**
- Jump between views from any context (errors to timeline, tasks to agents, analytics to feed, etc.)

**State Persistence:**
- View mode, filters, search query, selected team persist across page reloads via localStorage

## MCP Server

Observatory exposes an MCP server so Claude Code agents can check their inbox, send messages, and manage tasks.

### Tools

| Tool | Description |
|------|-------------|
| `check_inbox` | Get unread messages for an agent session |
| `acknowledge_message` | Mark a message as read |
| `send_message` | Send a message to another agent or dashboard |
| `get_tasks` | Get assigned tasks from the task board |
| `update_task_status` | Update task status (pending/in_progress/completed) |

### Connect agents

Add to your project's `.mcp.json`:

```json
{
  "mcpServers": {
    "observatory": {
      "type": "http",
      "url": "http://localhost:4005/mcp"
    }
  }
}
```

Or via CLI:

```bash
claude mcp add --transport http observatory http://localhost:4005/mcp
```

## Hook Scripts

Observatory receives events via shell hook scripts that POST JSON to `/api/events`. The hook script reads JSON from stdin, extracts session metadata, and fires a non-blocking POST to the Observatory server.

### 1. Install the hook script

```bash
mkdir -p ~/.claude/hooks/observatory
cp hooks/send_event.sh ~/.claude/hooks/observatory/send_event.sh
chmod +x ~/.claude/hooks/observatory/send_event.sh
```

The script requires `jq` and `curl`. It defaults to `http://localhost:4005/api/events` but respects the `OBSERVATORY_URL` environment variable.

### 2. Configure Claude Code hooks

Add the following to your `~/.claude/settings.json` (create it if it doesn't exist). This maps all 12 Claude Code lifecycle events to the hook script:

```json
{
  "hooks": {
    "SessionStart": [
      { "type": "command", "command": "~/.claude/hooks/observatory/send_event.sh SessionStart" }
    ],
    "SessionEnd": [
      { "type": "command", "command": "~/.claude/hooks/observatory/send_event.sh SessionEnd" }
    ],
    "PreToolUse": [
      { "type": "command", "command": "~/.claude/hooks/observatory/send_event.sh PreToolUse" }
    ],
    "PostToolUse": [
      { "type": "command", "command": "~/.claude/hooks/observatory/send_event.sh PostToolUse" }
    ],
    "PostToolUseFailure": [
      { "type": "command", "command": "~/.claude/hooks/observatory/send_event.sh PostToolUseFailure" }
    ],
    "UserPromptSubmit": [
      { "type": "command", "command": "~/.claude/hooks/observatory/send_event.sh UserPromptSubmit" }
    ],
    "PreCompact": [
      { "type": "command", "command": "~/.claude/hooks/observatory/send_event.sh PreCompact" }
    ],
    "PermissionRequest": [
      { "type": "command", "command": "~/.claude/hooks/observatory/send_event.sh PermissionRequest" }
    ],
    "Notification": [
      { "type": "command", "command": "~/.claude/hooks/observatory/send_event.sh Notification" }
    ],
    "SubagentStart": [
      { "type": "command", "command": "~/.claude/hooks/observatory/send_event.sh SubagentStart" }
    ],
    "SubagentStop": [
      { "type": "command", "command": "~/.claude/hooks/observatory/send_event.sh SubagentStop" }
    ],
    "Stop": [
      { "type": "command", "command": "~/.claude/hooks/observatory/send_event.sh Stop" }
    ]
  }
}
```

The script always exits 0 and uses a 1-second connect timeout so it never blocks Claude Code, even if Observatory is not running.

### 3. Verify

Start Observatory (`mix phx.server`) and open a new Claude Code session. You should see events appear in the Feed view immediately.

## Key Modules

| Module | Purpose |
|--------|---------|
| `Observatory.Events` | Ash domain for event/session resources |
| `Observatory.AgentTools` | Ash domain with AshAi MCP tools |
| `Observatory.Mailbox` | ETS-backed per-agent message queues |
| `Observatory.CommandQueue` | File-based inbox/outbox for agent communication |
| `Observatory.TaskManager` | JSON file CRUD for team task boards |
| `Observatory.TeamWatcher` | GenServer polling ~/.claude/teams/ for team state |
| `Observatory.AgentMonitor` | Crash detection + auto-task-reassignment |
| `ObservatoryWeb.DashboardLive` | Main LiveView coordinator (delegates to 7 handler modules) |
