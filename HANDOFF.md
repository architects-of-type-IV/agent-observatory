# Observatory - Handoff

## Current Status
Enhanced agent member cards in Agents view with activity data. Cards now show model, working directory, current tool execution, uptime, failure rate, and permission mode.

## What Was Done (card-enhancer agent)

### Agent Cards Enhanced
- Modified `dashboard_team_helpers.ex:enrich_team_members/3` to extract additional session data:
  - Model name from SessionStart events
  - Working directory (cwd) from most recent events
  - Permission mode from SessionStart payload
  - Current running tool (PreToolUse without matching PostToolUse)
  - Session uptime from first event to now
- Added helper functions: `extract_model_from_events/1`, `extract_cwd_from_events/1`, `extract_permission_mode/1`, `detect_current_tool/2`
- Added formatting helpers: `format_uptime/1`, `format_permission_mode/1` in dashboard_format_helpers.ex
- Updated dashboard_live.html.heex member cards to display all new data inline with existing badges

### Files Modified
- `lib/observatory_web/live/dashboard_team_helpers.ex` (239 lines)
- `lib/observatory_web/live/dashboard_format_helpers.ex` (248 lines)
- `lib/observatory_web/live/dashboard_live.html.heex`

### Display Features
Each member card now shows:
1. Model badge (opus/sonnet/haiku)
2. Abbreviated working directory (last 2 path segments)
3. Current activity: "Running: {tool_name} ({elapsed}s)" when tool executing
4. Session uptime (formatted as "Xm" or "Xh Ym")
5. Failure rate badge (red if >10%, amber if >5%, hidden if 0%)
6. Permission mode badge (e.g., "bypass" for bypassPermissions)

### Verified
- Zero warnings build (mix compile --warnings-as-errors)
- All modules under 300 lines
- Existing components reused (model_badge, abbreviate_cwd)

## Next Steps
- Agent detail panel with full inspection (task #2 - panel-builder)
- Continue Agents view enhancements per team plan
