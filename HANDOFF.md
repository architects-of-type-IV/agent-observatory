# Observatory MCP Server - Handoff

## Current Status
MCP server implemented and tested. Agents can connect to Observatory via MCP to check inbox, send messages, and manage tasks.

## What Was Done

### MCP Server (AshAi)
- Added `ash_ai` ~> 0.5 and `usage_rules` ~> 1.1 dependencies
- Created `Observatory.AgentTools` domain with AshAi extension
- Created `Observatory.AgentTools.Inbox` resource with 5 generic actions:
  - `check_inbox(session_id)` - returns unread messages
  - `acknowledge_message(session_id, message_id)` - mark as read
  - `send_message(from_session_id, to_session_id, content)` - send via Mailbox
  - `get_tasks(session_id, team_name)` - list assigned tasks
  - `update_task_status(team_name, task_id, status)` - update task status
- Forwarded `/mcp` in Phoenix router to `AshAi.Mcp.Router`
- Registered `Observatory.AgentTools` domain in config
- Created `.mcp.json` at project root for Claude Code integration

### Files Created/Modified
- `lib/observatory/agent_tools.ex` (new - Ash Domain)
- `lib/observatory/agent_tools/inbox.ex` (new - Ash Resource with actions)
- `lib/observatory_web/router.ex` (added MCP forward)
- `config/config.exs` (added AgentTools domain)
- `mix.exs` (added ash_ai, usage_rules deps)
- `../../.mcp.json` (project root - Claude Code MCP config)

### Verified
- MCP initialize handshake works (protocol 2025-03-26)
- tools/list returns all 5 tools with JSON schemas
- tools/call works: send_message + check_inbox tested end-to-end
- Zero warnings build

## Agent Connection
Agents in the kardashev project auto-discover Observatory via `.mcp.json`:
```
claude mcp add --transport http observatory http://localhost:4005/mcp
```

## Next Steps
- Agents view analysis and improvements (user requested)
- Consider adding a PostToolUse hook to inject "you have messages" context
- Test with actual Claude Code agent sessions
