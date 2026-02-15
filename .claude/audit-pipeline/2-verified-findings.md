# Stage 2: Verified Findings

CONFIRMED: 19
REJECTED: 2 (false positives)
REVIEW: 0

## CONFIRMED -- Delete

### Unused functions (4)
- F1: Repo.installed_extensions/0 (repo.ex:6-8)
- F2: CommandQueue.poll_responses/1 (command_queue.ex:34-36)
- F3: CommandQueue.get_pending_commands/1 (command_queue.ex:41-43)
- F4: Channels.remove_team_channel/1 (channels.ex:149-153)

### Unused Ash domains + resources (6) -- also remove from config.exs
- F5: Observatory.Messaging.Message (messaging/message.ex)
- F6: Observatory.Messaging (messaging.ex)
- F7: Observatory.TaskBoard.Task (task_board/task.ex)
- F8: Observatory.TaskBoard (task_board.ex)
- F9: Observatory.Annotations.Note (annotations/note.ex)
- F10: Observatory.Annotations (annotations.ex)

### Unused LiveView functions (4)
- F11: add_search_to_history (dashboard_filter_handlers.ex:110)
- F12: filter_threads_by_participant (dashboard_message_helpers.ex:55)
- F13: extract_participants (dashboard_message_helpers.ex:129)
- F14: handle_edit_task (dashboard_task_handlers.ex:122)

### Dead components (3 files + 3 delegations in observatory_components.ex)
- F19: toast_container.ex
- F20: session_dot.ex
- F21: event_type_badge.ex

### Dead infrastructure (3 files + 1 macro + 1 test)
- F22: page_controller.ex, page_html.ex, page_html/home.html.heex
- F23: ObservatoryWeb.channel/0 macro (observatory_web.ex:33-36)
- page_controller_test.exs

## CONFIRMED -- Change def to defp (3)
- F16: group_events_by_session (dashboard_feed_helpers.ex)
- F17: pair_tool_events (dashboard_feed_helpers.ex)
- F18: detect_tool_loops (dashboard_agent_health_helpers.ex)

## REJECTED (false positives)
- F15: short_model_name -- USED in model_badge.ex:24
- Mailbox.broadcast_to_many -- USED in inspector handlers
