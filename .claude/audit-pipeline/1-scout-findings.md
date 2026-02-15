# Stage 1: Scout Findings - Dead Code Audit

Found **23 instances** across **~20 files** from 4 parallel scouts.

## Backend (lib/observatory/)

### F1: Repo.installed_extensions/0 -- unused function
- File: lib/observatory/repo.ex:6-8
- Confidence: HIGH

### F2: CommandQueue.poll_responses/1 -- unused function
- File: lib/observatory/command_queue.ex:34-36
- Confidence: HIGH

### F3: CommandQueue.get_pending_commands/1 -- unused function
- File: lib/observatory/command_queue.ex:41-43
- Confidence: HIGH

### F4: Channels.remove_team_channel/1 -- unused function
- File: lib/observatory/channels.ex:149-153
- Confidence: HIGH

### F5-F10: Unused Ash resources + domains (6 items)
- Observatory.Messaging.Message (lib/observatory/messaging/message.ex)
- Observatory.Messaging (lib/observatory/messaging.ex)
- Observatory.TaskBoard.Task (lib/observatory/task_board/task.ex)
- Observatory.TaskBoard (lib/observatory/task_board.ex)
- Observatory.Annotations.Note (lib/observatory/annotations/note.ex)
- Observatory.Annotations (lib/observatory/annotations.ex)
- All HIGH confidence -- app uses ETS/file alternatives

## LiveView (lib/observatory_web/live/)

### F11: add_search_to_history -- unused (dashboard_filter_handlers.ex:110)
### F12: filter_threads_by_participant -- unused (dashboard_message_helpers.ex:55)
### F13: extract_participants -- unused (dashboard_message_helpers.ex:129)
### F14: handle_edit_task -- unused (dashboard_task_handlers.ex:122)
### F15: short_model_name -- unused (dashboard_session_helpers.ex:56)
### F16-F18: Should-be-private (group_events_by_session, pair_tool_events, detect_tool_loops)

## Components (lib/observatory_web/components/)

### F19: toast_container.ex -- dead component (never called)
### F20: session_dot.ex -- dead component (never called)
### F21: event_type_badge.ex -- dead component (never called)

## Infrastructure

### F22: PageController + PageHTML + template -- no route (3 files)
### F23: ObservatoryWeb.channel/0 -- dead macro

## Rejected (false positives)
- Mailbox.broadcast_to_many/4: Called from inspector handlers
- team_summary/1: Called from teams_components.ex
- Observatory module: Intentional namespace root
