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

1. **Overview** - Stat cards (teams, agents, tasks, errors) + recent activity feed
2. **Feed** - Real-time event stream with search, filters, and duration indicators
3. **Tasks** - Kanban board (pending/in-progress/completed) with create/edit from UI
4. **Messages** - Inter-agent message threads with search, collapsible threads, type badges
5. **Agents** - Team grid with health monitoring, activity indicators, model/cwd/uptime badges, detail panel
6. **Errors** - Grouped error dashboard with acknowledge actions
7. **Analytics** - Tool performance leaderboard and slowest calls
8. **Timeline** - Horizontal swimlanes per session with tool execution blocks

Keyboard shortcuts: `?` for help, `1-8` for views, `f` for filter, `j/k` to navigate.

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
