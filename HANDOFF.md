# Observatory - Handoff

## Current Status: MCP Messaging Pipeline Verified Working

## What Happened This Session

Tested `/orchestrate` on a real task: verify the Mailbox MCP server works end-to-end for dashboard-to-agent messaging. Used FIX-LOOP workflow.

### FIX-LOOP Results

**REPRODUCE**: Tested all 5 MCP tools via curl and direct MCP tool calls.

**DIAGNOSE**: Traced full messaging pipeline:
- Dashboard -> Agent: LiveView form -> `Mailbox.send_message/4` -> ETS + CommandQueue (filesystem)
- Agent -> Dashboard: MCP `send_message` -> Mailbox -> ETS + PubSub broadcast
- Agent inbox: MCP `check_inbox` -> Mailbox -> ETS lookup
- Agent ack: MCP `acknowledge_message` -> Mailbox -> mark read
- Task ops: MCP `get_tasks` / `update_task_status` -> TaskManager

**VERIFY**: All 5 MCP tools work correctly:
- `send_message` -- delivers to ETS + writes `~/.claude/inbox/{session_id}/{id}.json`
- `check_inbox` -- returns unread messages from ETS
- `acknowledge_message` -- marks as read
- `get_tasks` -- returns tasks (empty when none assigned)
- `update_task_status` -- updates task status

### Findings

1. **Not a bug**: Earlier curl test failure was zsh history expansion mangling `!` in shell. Using file input (`-d @file.json`) or MCP tools directly works fine.
2. **AshAi argument nesting**: AshAi expects tool arguments under `"input"` key: `{"arguments": {"input": {"from_session_id": ...}}}`. This is handled automatically by MCP clients.
3. **Unused Ash resource**: `Observatory.Messaging.Message` is defined but never used. Messages only live in ETS (lost on restart) and filesystem. Future consideration.
4. **Server runs on port 4005** (not 4000).

## No Code Changes
The observatory repo has no uncommitted changes. The messaging pipeline was already correctly implemented.

## Team Inspector Scout - 2026-02-15
### Data Structure Analysis (READ-ONLY)

Completed analysis of all team-related data structures for team-inspector project:

**Key data flows identified:**
- TeamWatcher polls `~/.claude/teams/` and `~/.claude/tasks/` every 2s
- Teams come from two sources: disk (TeamWatcher) and events (hook events)
- DashboardTeamHelpers merges both sources, disk is authoritative
- Members enriched with health, status, model, cwd, current_tool, uptime from events
- PubSub topics: `teams:update`, `team:{name}`, `agent:{id}`, `session:{id}`, `events:stream`, `agent:crashes`

**Gaps for team inspector:**
- No team-level aggregate health/progress metrics
- No task completion percentage per team
- No message volume/flow tracking between members
- No team timeline (when created, duration, phases)
- No roadmap integration (`.claude/roadmaps/` not read by TeamWatcher)

## Next Steps
- Consider persisting messages via `Observatory.Messaging.Message` Ash resource
- Test messaging from the actual browser dashboard UI (LiveView form)
- Consider adding message history view in dashboard
