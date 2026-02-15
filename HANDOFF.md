# Observatory - Handoff

## Current Status: Dashboard Message Forms Unified

Fixed all 4 dashboard-to-agent message forms to use consistent delivery (Mailbox) and UX (phx-update="ignore" + JS form clear).

## What Was Fixed

### Phase 1: Discovery (team: messaging-discovery, 3 agents)
Found 5 critical gaps + 1 bug:
1. Dashboard not subscribed to "agent:dashboard" PubSub topic
2. No :current_session_id assign in mount
3. subscribe_to_mailboxes() skips dashboard
4. acknowledge_message doesn't clean CommandQueue files
5. ~/.claude/inbox/ is custom, not Claude Code native path
6. Form refresh bug: :tick timer recreates teams list, destroying form DOM

### Phase 2: Analysis (team: messaging-analysis, 3 agents)
- **Architecture**: Option B chosen (align with Claude Code native paths)
- **Form bug root cause**: prepare_assigns() runs every 1s tick, creates new list reference, LiveView re-renders message_composer
- **Reliability**: 164 stale files in inbox, no ETS TTL, duplicate delivery risk

### Phase 3: Implementation (team: messaging-fix, 3 agents)
All fixes applied:

1. **PubSub subscription** (dashboard_live.ex:27)
   - Added `Phoenix.PubSub.subscribe(Observatory.PubSub, "agent:dashboard")`
   - Added `assign(:current_session_id, "dashboard")`

2. **Form refresh fix** (dashboard_live.html.heex)
   - Wrapped message_composer with `<div phx-update="ignore" id="message-composer-stable">`
   - Wrapped agent message form with `<div phx-update="ignore" id="agent-message-form-stable">`

3. **CommandQueue aligned with Claude Code native** (command_queue.ex)
   - Added write_team_message/3 -> ~/.claude/teams/{team}/inboxes/{agent}.json
   - Added delete_team_message/3 for cleanup
   - Mailbox.send_message now dual-writes: legacy + native format
   - Agent ID parsed: "name@team" -> split to get team/agent

4. **Acknowledge cleanup** (agent_tools/inbox.ex)
   - acknowledge_message now deletes CommandQueue file after ETS mark_read

5. **ETS TTL** (mailbox.ex)
   - Added :cleanup_old_messages timer (60s interval)
   - Removes read messages older than 24h

## Latest Changes: Message Form Consistency (2026-02-15)

### Problem
4 message forms used 3 different delivery mechanisms. `send_team_broadcast` bypassed Mailbox entirely (direct CommandQueue + PubSub). Forms in Agents view lacked `phx-update="ignore"` (input lost on 1s tick). All `phx-update="ignore"` forms didn't clear after submit.

### Fixes Applied
1. **dashboard_messaging_handlers.ex**: `send_team_broadcast` now uses `Mailbox.broadcast_to_many` (ETS + CommandQueue + PubSub)
2. **agents_components.ex**: Added `phx-update="ignore"` wrappers to broadcast + per-agent forms
3. **app.js**: Added `ClearFormOnSubmit` hook to reset text inputs after submit
4. **dashboard_live.html.heex**: Added `ClearFormOnSubmit` hook to existing `phx-update="ignore"` wrappers

### Also Created
- `.claude/skills/team-task/SKILL.md` -- Agent protocol skill for team-based task execution
- Insights report stored at `~/.config/claude/reports/report-1771120758.html`

## Build Status
`mix compile --warnings-as-errors` -- PASSES (zero warnings)

## Roadmap
`.claude/roadmaps/roadmap-1771119705/` (messaging investigation)
