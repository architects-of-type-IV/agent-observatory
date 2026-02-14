# Observatory - Handoff

## Current Status
All Agents view improvements complete. MCP server operational. README fully documented with hook setup instructions.

## What Was Done This Session

### Hook Setup Instructions in README
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

## Files Modified
- `README.md` (rewritten with full docs + hook setup)
- `observatory/.mcp.json` (new)
- `lib/observatory/agent_tools.ex` (new)
- `lib/observatory/agent_tools/inbox.ex` (new)
- `lib/observatory_web/router.ex` (added /mcp route)
- `config/config.exs` (added AgentTools domain)
- `mix.exs` (added ash_ai, usage_rules)
- `lib/observatory_web/live/dashboard_team_helpers.ex` (239 lines)
- `lib/observatory_web/live/dashboard_format_helpers.ex` (248 lines)
- `lib/observatory_web/live/dashboard_agent_helpers.ex` (new, 34 lines)
- `lib/observatory_web/live/dashboard_live.ex` (245 lines)
- `lib/observatory_web/live/dashboard_live.html.heex`

## Verified
- Zero warnings: mix compile --warnings-as-errors
- All modules under 300 lines
- MCP server tested end-to-end (initialize, tools/list, tools/call)

## Next Steps
- Session control actions (pause/resume/shutdown agents from UI)
- Inline task editing in agent detail panel
- Cost tracking and budgets
- Session replay functionality
