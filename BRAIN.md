# Observatory - Brain

## Architecture
- Event-driven: hooks -> POST /api/events -> Ash.create + PubSub.broadcast -> LiveView
- Dual data sources: event-derived state + disk-based team/task state (TeamWatcher)
- prepare_assigns/1 called from mount and every handle_event/handle_info

## Patterns
- Module size limit: 200-300 lines max
- Template in separate .html.heex file, not inline ~H
- Helper functions split by domain:
  - dashboard_team_helpers.ex: team derivation, member enrichment
  - dashboard_data_helpers.ex: task/message derivation, filtering
  - dashboard_format_helpers.ex: display formatting, event summaries
  - dashboard_messaging_handlers.ex: messaging event handlers
- Reusable components in observatory_components.ex
- GenServers: TeamWatcher (disk polling), Mailbox (ETS message queues)
- Phoenix.Component.assign/3 for helper modules (not LiveView.assign/2)

## Refactoring Lessons
- Extract template FIRST (biggest win), then helpers, then components
- prepare_assigns/1 pattern: single function that computes all derived assigns from raw state
- Keep LiveView module to lifecycle only: mount, handle_info, handle_event, prepare_assigns

## Team Agent Insights
- Teammates spawned in delegate mode may lack file tools (Read, Bash) - verify tool access
- Always spawn with mode: "bypassPermissions" for implementation work
- subagent_type: "general-purpose" should have all tools but doesn't always
- One team per leader limitation - add tasks to existing team instead of creating new ones
- Always review teammate work - don't trust completion messages blindly

## PubSub Topics
- "events:stream" - all events (dashboard subscribes)
- "teams:update" - team state changes from TeamWatcher
- "agent:{session_id}" - per-agent mailbox channel
- "team:{team_name}" - team broadcast channel
- "session:{session_id}" - session event stream
- "dashboard:commands" - UI -> agents commands

## User Preferences
- Zero warnings policy
- Modules under 300 lines
- Always run builds (mix compile --warnings-as-errors)
- Always verify work as team lead
- Use /keep-track for checkpoints
