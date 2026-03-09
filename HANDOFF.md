# ICHOR IV (formerly Observatory) - Handoff

## Current Status: Legacy Elimination Complete (2026-03-09)

### Just Completed

**Phase 2: Eliminate legacy modules (task 51)**

Removed Mailbox, CommandQueue, and TeamWatcher GenServers entirely. Zero references remain.

Changes made:
- **CoreSupervisor**: removed 3 children (Mailbox, CommandQueue, TeamWatcher)
- **MailboxAdapter**: rewired from Mailbox.send_message to AgentProcess.send_message
- **LoadMessages**: removed Mailbox.all_messages merge, now hook events only
- **LoadTeams**: removed TeamWatcher.get_state disk merge, now events + BEAM teams only
- **Fleet.Agent mark_read**: converted to no-op (get_unread is destructive read)
- **Operator.fallback_deliver**: replaced Mailbox.send_message with PubSub broadcast
- **Fleet.Team source constraint**: removed :disk from allowed values
- **Deleted modules**: mailbox.ex, command_queue.ex, team_watcher.ex (moved to tmp/trash/)

### Previously Completed (same session)

**Phase 1: Rewire all callers to Fleet code interfaces (task 42)**
- All external callers rewired to Fleet.Agent/Fleet.Team/Activity.Message code interfaces
- Fixed :pg child spec, HostRegistry scope, Ash domain config

### .env Setup
- `ANTHROPIC_API_KEY` in `.env` at project root
- Not auto-loaded -- `source .env` before `mix phx.server`

### Build Status
`mix compile --warnings-as-errors` -- CLEAN

### Next Steps
1. **Task 8** (pending, low priority): Non-blocking event pipeline validation
2. **Task 31** (pending, low priority): Rename codebase to ICHOR IV
3. **Tasks 38-40**: Now redundant (legacy modules already eliminated by task 51)
4. Claude-specific disk scanning (~/.claude/teams/) deferred per user directive

### Memories Server
- Running on port 4000 (must be running for Archon memory tools)
- Requires Docker: postgres (port 5434) + falkordb (port 6379)
- ONNX models on external drive: `/Volumes/T5/models/ONNX`
