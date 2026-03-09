# ICHOR IV (formerly Observatory) - Handoff

## Current Status: Fleet Consistency Rewire (2026-03-09)

### Just Completed

**Phase 1: Rewire all callers to Fleet code interfaces (task 42, subtasks 42.1-42.5)**

All external callers of legacy modules (Mailbox, CommandQueue, TeamWatcher) now route through
Fleet.Agent, Fleet.Team, Activity.Message, and Operator.send code interfaces instead of
calling legacy GenServers directly.

Rewired modules:
- **Archon.Tools.Agents** -> Fleet.Agent.all!/active! (was AgentRegistry.list_all)
- **Archon.Tools.Teams** -> Fleet.Team.alive! (was TeamWatcher.get_state)
- **Archon.Tools.System** -> Fleet.Agent.all!/Fleet.Team.alive! (was AgentRegistry + TeamWatcher)
- **Archon.Tools.Messages** -> Activity.Message.recent! (was Mailbox.all_messages)
- **AgentTools.Inbox** -> Fleet.Agent.get_unread/mark_read/send_message (was AgentProcess + Mailbox direct)
- **DashboardSessionControlHandlers** -> Operator.send (was CommandQueue.write_command + Mailbox.send_message)
- **DashboardState** -> Activity.Message.recent! mapped to legacy format (was Mailbox.all_messages)
- **DashboardMessagingHandlers** -> simplified refresh_mailbox_assigns (was Mailbox.unread_count)
- **DashboardLive.mount** -> empty map (was TeamWatcher.get_state; Fleet.Team reads handle disk internally)
- **DebugController** -> Fleet.Team/AgentProcess/Activity.Message (was TeamWatcher + Mailbox)

New Fleet.Agent actions added: `get_unread`, `mark_read` (with code interfaces).

### Also Fixed This Session

- **:pg child spec** in application.ex -- Erlang module needs explicit child spec map
- **HostRegistry :pg scope** -- was using :pg.join/2 (default scope), fixed to :pg.join/3 with :observatory_agents
- **Ash domain config** -- added Observatory.Archon + Observatory.Archon.Tools to ash_domains

### .env Setup
- `ANTHROPIC_API_KEY` in `.env` at project root
- Not auto-loaded -- `source .env` before `mix phx.server`

### Build Status
`mix compile --warnings-as-errors` -- CLEAN

### Next Steps
1. **Task 51: Eliminate legacy modules** (Phase 2) -- Remove Mailbox, CommandQueue, TeamWatcher
   - Rewire MailboxAdapter to deliver via AgentProcess
   - Remove legacy modules from CoreSupervisor
   - Update LoadTeams/LoadMessages to not need legacy modules
   - Claude-specific disk scanning (TeamWatcher ~/.claude/teams/) deferred
2. **Remaining tasks**: 8 (pipeline validation), 31 (rename), 38-40 (legacy cleanup, blocked by 51)

### Memories Server
- Running on port 4000 (must be running for Archon memory tools)
- Requires Docker: postgres (port 5434) + falkordb (port 6379)
- ONNX models on external drive: `/Volumes/T5/models/ONNX`
