# Observatory - Handoff

## Current Status (Sprint 5)
Task #1 COMPLETED: Created Ash resources for Messages, Tasks, Notes, and Costs to replace ETS/file-based storage.

## What Was Done This Session (Sprint 5)

### Ash Resources Created (Task #1)
Created four new Ash domains with SQLite-backed resources:

1. **Observatory.Messaging** - Message storage (replaces Mailbox ETS)
   - Resource: Observatory.Messaging.Message (103 lines)
   - Attributes: from_session_id, to_session_id, content, message_type (enum: message, broadcast, shutdown_request, shutdown_response, plan_approval_request, plan_approval_response), read (boolean), team_name
   - Actions: create, read, mark_read, unread_for_session, by_thread

2. **Observatory.TaskBoard** - Task management (replaces TaskManager JSON files)
   - Resource: Observatory.TaskBoard.Task (123 lines)
   - Attributes: subject, description, status (enum: pending, in_progress, completed), owner, team_name, active_form, blocks (array), blocked_by (array), metadata (map)
   - Actions: create, read, update, by_team, by_owner

3. **Observatory.Annotations** - Event notes (replaces Notes ETS)
   - Resource: Observatory.Annotations.Note (63 lines)
   - Attributes: event_id, text
   - Actions: create, read, update, delete, by_event

4. **Observatory.Costs** - Token usage tracking (NEW feature)
   - Resource: Observatory.Costs.TokenUsage (118 lines)
   - Attributes: session_id, source_app, model_name, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, estimated_cost_cents, tool_name
   - Actions: create, read, by_session, by_model, totals
   - Calculations: total_input_tokens, total_output_tokens, total_cost_cents

### Previous Session: Hook Setup Instructions in README
- Added full "Hook Scripts" section to README.md with 3-step setup guide:
  1. Install script: copy `send_event.sh` to `~/.claude/hooks/observatory/`
  2. Configure hooks: complete JSON config for all 12 Claude Code lifecycle events
  3. Verify: start server + open Claude Code session
- Documents `OBSERVATORY_URL` env var, `jq`/`curl` requirements, non-blocking behavior

### Agent Detail Panel (panel-builder agent)
- Created `dashboard_agent_helpers.ex` (34 lines):
  - `agent_recent_events/3` - filters events to last N for specific agent
  - `agent_tasks/2` - filters tasks by owner matching agent_id
- Modified `dashboard_live.ex` (245 lines):
  - Added `:selected_agent` assign with toggle behavior
  - Consolidated event handlers to single-line format (313 -> 245 lines)
  - `clear_selections/0` helper for mutual exclusion across selection types
- Updated `dashboard_live.html.heex`:
  - Clickable member cards with `phx-click="select_agent"`
  - Right sidebar panel: header, details, health metrics, recent 15 events, assigned tasks, message input, actions

### Agent Member Card Enhancement (card-enhancer agent)
- Enhanced `dashboard_team_helpers.ex` (239 lines):
  - `enrich_team_members/3` extracts model, cwd, permission_mode, current_tool, uptime
  - `detect_current_tool/2` finds PreToolUse without matching PostToolUse
- Enhanced `dashboard_format_helpers.ex` (248 lines):
  - `format_uptime/1`, `format_permission_mode/1`
- Cards now show: model badge, cwd, current activity, uptime, failure rate, permission mode

### MCP Server (earlier in session)
- AshAi MCP server at `/mcp` with 5 tools (check_inbox, acknowledge_message, send_message, get_tasks, update_task_status)
- `.mcp.json` config for agent connection

## Files Created (Sprint 5)
- `lib/observatory/messaging/message.ex` (103 lines)
- `lib/observatory/messaging.ex` (7 lines)
- `lib/observatory/task_board/task.ex` (123 lines)
- `lib/observatory/task_board.ex` (7 lines)
- `lib/observatory/annotations/note.ex` (63 lines)
- `lib/observatory/annotations.ex` (7 lines)
- `lib/observatory/costs/token_usage.ex` (118 lines)
- `lib/observatory/costs.ex` (7 lines)

## Files Modified (Sprint 5)
- `config/config.exs` (added 4 new domains to ash_domains list)

## Database Changes (Sprint 5)
- Migration generated: `priv/repo/migrations/20260214201807_sprint5_domains.exs`
- Migration applied: 4 new tables (messages, tasks, notes, token_usages)
- Resource snapshots created for all 4 resources

## Verified (Sprint 5)
- Zero warnings: `mix compile --warnings-as-errors` passed
- All modules under 300 lines (largest: TaskBoard.Task at 123 lines)
- Followed existing pattern from Observatory.Events.Event
- All 4 domains registered in config

## Next Steps
- Task #2: Split dashboard_live.html.heex into per-view component files (template-splitter working on this)
- Task #3: Add session control actions (pause/resume/shutdown agents)
- Task #4: Add inline task editing in task cards and detail panel
- Task #5: Quality control: verify all changes, fix warnings, test endpoints

## Important Notes
- Do NOT modify existing GenServers (mailbox.ex, task_manager.ex, notes.ex, command_queue.ex) - integration is a separate task
- The Ash resources are ready but not yet integrated with existing code
- All resources use AshSqlite.DataLayer with Observatory.Repo
- Pattern followed: lib/observatory/events/event.ex as reference
