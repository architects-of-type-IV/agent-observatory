Let me systematically find and read all fleet-related files.
Now let me read the core fleet-specific files.
Now let me read the session control handlers, command components, and the status bar component.
Now let me read the info handlers to understand how the fleet data is updated via PubSub, and the DAG handlers for the fleet's launch session feature.
Now let me check the messaging handlers and spawn handlers used in the fleet view.
I now have enough information to write a comprehensive analysis. Let me do one final check on the spawn handlers to understand the `spawn_agent` and `stop_spawned_agent` events.
Here is a complete description of all features on the /fleet page.

---

# /fleet Page: Complete Feature Description

## Navigation and Entry Point

The fleet page is reached via the left navigation bar at `/fleet` (URL param `view=fleet` or just `/fleet`). The nav item is a "group of people" SVG icon with tooltip "Fleet Control". The active state highlights it with `bg-interactive/20 text-interactive`. Navigating here sets `nav_view = :fleet` via `handle_params` in `DashboardLive`.

The view renders `IchorWeb.Components.CommandComponents.command_view` passing a large set of assigns.

---

## Layout

Three-column layout at full viewport height:

1. Left panel (280px fixed): Agent list (the "Fleet" roster)
2. Center (flex-1): Command bar + tab bar + either Comms timeline or Feed
3. Right panel (400px, conditional): Agent detail panel, only visible when an agent is selected

---

## Left Panel: Agent Roster

**Data source:** `@agent_index` -- a map built in `DashboardState.recompute/1` from `Ichor.Control.Agent.all!()`, merged with team membership data and tmux session names. The "operator" agent is explicitly excluded from the list.

**Sorting:** Agents sorted by `{status_sort_val(status), name}`. Active agents appear first (sort val 0), idle second (1), everything else last (2).

**Per-agent row elements:**
- Status dot: colored circle (`success` = active, `default` = idle, `muted` = other) from `member_status_dot_class/1`
- Agent name (truncated)
- Team name badge (dim, 8px mono, shown only when present and non-empty)
- PAUSED badge: uppercase, brand-colored, shown when `session_id` is in `paused_sessions` MapSet
- Tmux indicator: shows "tmux" in brand color when the agent has a tmux channel, "no-tmux" in error red when it does not
- Model shortname: "opus", "sonnet", or "haiku" depending on `agent[:model]`

**Selection:** Clicking a row fires `select_command_agent` with `id = agent[:agent_id]`. If the same agent is already selected, it deselects (toggle). The selected row gets `bg-interactive/10 border-l-2 border-interactive`.

**Empty state:** When no agents are detected, shows "No agents detected / Start a Claude session to see it here."

**Header:** Shows total agent count.

---

## Center Panel: Command Bar

A persistent bar at the top of the center column, always visible regardless of active tab.

**Broadcast/targeted message form (`send_targeted_message`):**
- Target dropdown (`phx-update="ignore"` for DOM stability): Options grouped into "Broadcast" (all agents, per-team) and "Agents" (individual agents by name + team hint). Value can be `"all"`, `"team:TeamName"`, or an `agent_id`.
- Text input: message content
- Submit: `Send` button. Routes through `DashboardMessagingHandlers.handle_send_targeted_message/2`, which calls `Ichor.Messages.Bus.send/1` with `from: "operator"`, `transport: :operator`. Toast shown on success (channel count) or warning (no delivery channel). No-ops on empty content or empty target.

**Launch session form (`launch_session`):**
- Project dropdown (`phx-update="ignore"`): Populated from `@dag_state.watched_projects`, key/path pairs.
- Submit: `Launch` button. Routes to `DashboardTmuxHandlers.handle_launch_session/2`, which calls `Ichor.Control.Lifecycle.AgentLaunch.spawn(%{cwd: cwd})`. Toast on success or error. No-ops if no project is selected.

---

## Center Panel: Tab Bar

Two tabs: "Comms" and "Feed". Tab state is `@activity_tab` (default `:comms`). Switching fires `set_sub_tab` with `screen: "activity"` and `tab: "comms"|"feed"`.

---

## Center Panel Tab: Comms

**Data source:** `@mailbox_messages` -- a merged, deduplicated list of the last 50 messages from `Ichor.Messages.Bus.recent_messages(50)` (operator-sent messages) and `Ichor.Observability.Message.recent!()` (hook-delivered messages), sorted by timestamp descending.

**Filtering:** Two filter dimensions applied in sequence:
1. Team filter (`comms_team_filter`): Shows only messages where `from` or `to` matches a team member's session_id, or `from`/`to` is `"operator"`. Team pills shown in the tab bar header; clicking the same team again clears the filter; "All" clears to nil.
2. Agent trace filter (`comms_agent_filter`): A list of up to 2 agent IDs. When 1 ID: shows messages involving that agent. When 2 IDs: shows only messages between those two agents. A purple "Trace:" label with removable agent chips appears when active. "x" button fires `clear_trace`.

**Message count** shown in the tab bar header: `{length(filtered_messages)} msgs`.

**Per-message row elements:**
- From label (resolved via `FH.resolve_label/2` using `name_map` that merges team member names and agent registry names)
- Arrow icon
- To label (same resolution)
- Read/unread badge: green "read" or brand-colored "unread"
- Transport badge: `mcp` (interactive), `operator` (brand), `hook` (warning), or `http` (success, the fallback)
- Timestamp (HH:MM:SS)
- Message content (full text, 11px)
- Delivery channel indicator ("mailbox" with green dot)
- Message type, if not `:text`

Operator-sent messages get a left border accent (`border-l-2 border-brand/30`).

**Empty state:** Instructional text: "Send a message from the command bar above, or use the MCP API."

---

## Center Panel Tab: Feed

**Data source:** `@feed_groups` -- built by `DashboardFeedHelpers.build_feed_groups/2` from events and tmux sessions. Groups events by session/turn.

**Controls in tab bar:**
- "Expand" button: fires `expand_all`
- "Collapse" button: fires `collapse_all`
- Session count: `{length(@feed_groups)} sessions`

**Content:** Renders `FeedComponents.feed_view/1` component with `feed_groups`, `visible_events`, `selected_event`, `event_notes`, `expanded_sessions`, and `now`.

Feed sessions are individually collapsible via `toggle_session_collapse`.

---

## Right Panel: Agent Detail (conditional, shown when an agent is selected)

Visible only when `@selected_command_agent` is set. Closes via `clear_command_selection`.

**Agent resolution:** Uses `agent_index[sel_id]` for live data, falls back to `selected_command_agent` struct. Team membership is found by scanning `@teams[].members` for a matching `agent_id`.

**Section: Info**
- Status (with "(HITL paused)" appended when applicable)
- Model name
- Role
- Team
- Working directory (basename only, full path as title tooltip)

**Section: Recent Messages**
Only shown when messages exist. Shows up to 4 messages involving the selected agent (matched by `agent_id` or `session_id`). Each message shows: sent/recv indicator, direction label, counterparty name, timestamp, and content (line-clamped to 2 lines).

**Section: Actions**
Buttons present conditionally:
- "Tmux": shown only if `sel_agent[:tmux_session]` is set. Fires `connect_tmux` to open the tmux multi-panel viewer.
- "Focus": always shown. Fires `open_agent_slideout` to open the agent focus slideout overlay.
- "Trace"/"Tracing" toggle: fires `trace_agent` with `agent_id`. Highlights in violet when active. Activates the agent trace filter and switches center panel to the Comms tab.
- "Pause" (when not HITL-paused): fires `pause_agent`. Calls `HITLRelay.pause/4`, sends a `Bus` session_control message, adds session to `paused_sessions`, subscribes to `gate_open`/`gate_close` signals, shows Archon overlay with HITL notification.
- "Resume" (when HITL-paused): fires `resume_agent`. Calls `HITLRelay.unpause/3`, sends resume Bus message, flushes buffered messages, removes from `paused_sessions`. Toast: "buffered messages flushed".
- "Shutdown": fires `shutdown_agent`. Sends shutdown Bus message, kills tmux session, stops `AgentProcess` via `FleetSupervisor` or `TeamSupervisor` (or direct `GenServer.stop` fallback), tombstones the session in `EventRuntime`, emits `:agent_stopped` signal, clears `selected_command_agent`.

**Section: HITL Gate (conditional, shown when agent is HITL-paused)**
- Header: "HITL Gate Open" in brand color with buffered message count
- Explanation text
- Buffered message list (up to scroll, shows index + content preview via `inspect/2`)
- "Approve & Flush" button: fires `hitl_approve`. Calls `HITLRelay.unpause/3`, emits `:hitl_operator_approved` signal. Toast shows count of flushed messages or "Session was not paused".
- "Reject" button: fires `hitl_reject` with `data-confirm` dialog. Calls `HITLRelay.reject/3`, emits `:hitl_operator_rejected` signal. Toast: "buffered messages discarded".

**Section: Send Message**
Direct message form targeting the selected agent specifically. `to` is a hidden field set to `sel_id`. Fires `send_command_message`, which calls `Bus.send/1` with `from: "operator"`, `transport: :operator`. Form is wrapped in `phx-update="ignore"` with a unique `id` keyed to `sel_id` to prevent DOM replacement on recompute. Uses `ClearFormOnSubmit` hook to clear input after send.

---

## Global Header: Fleet Status Bar

Present on all views (not just /fleet), rendered in the header as `fleet_status_bar`. It computes and displays:

- **Agent counts:** Total agents with breakdown: `Xa` (active, success color), `Xi` (idle, default color), `Xe` (ended, muted). Full counts shown as tooltip.
- **Error indicator:** Red dot + count if tool errors exist (from `@errors`).
- **Message count:** `Xmsg` from `@messages`.
- **Tool call count:** Sum of `tool_count` across all agents.
- **Event ratio:** `visible/total events`.
- **Task progress bar:** 12px wide, success-colored fill showing `done/total` ratio. Only shown when tasks exist.
- **Pipeline progress bar:** Cyan-colored, shown when pipeline total differs from task count.
- **Health badge:** Green "OK" or red pulsing dot with error/issue count. Combines `dag_state.health.healthy`, `dag_state.health.issues`, and `error_count`.
- **Protocol stats:** Shows `T:X` (traces), `M:X` (mailbox pending), `Q:X` (command queue pending) when any are nonzero.

---

## Real-Time Update Mechanism

The fleet page receives live updates via PubSub signals. The `DashboardInfoHandlers` debounces recomputes at 100ms. Signals that trigger fleet data refresh:

- `:agent_spawned`, `:agent_stopped`, `:registry_changed`, `:fleet_changed` -- all trigger `schedule_recompute` (full Ash queries)
- `:agent_crashed` -- triggers recompute + notification handler
- `:gate_open`, `:gate_close` -- refreshes `paused_sessions` directly from `HITLRelay.paused_sessions()`
- `:mailbox_message` -- routes to `DashboardMessagingHandlers.handle_new_mailbox_message/2`
- `:dag_status`, `:protocol_update` -- update `dag_state` and `protocol_stats` directly (used in status bar)
- `:terminal_output` -- updates `slideout_terminal` if the slideout is open for that session

---

## Agent Slideout Overlay (accessible from fleet detail panel)

A global overlay (defined in `dashboard_live.html.heex`, not fleet-specific, but accessible from fleet). Triggered by "Focus" button. A 480px right-side drawer showing:
- Agent metadata: status dot, name, session ID prefix, role, team, CWD, channels
- Terminal output section: last ANSI-rendered terminal output for the agent (from `:terminal_output` signals), with character count
- Activity feed: up to 50 activity items (events and messages) with type-colored dots, content, and timestamp
- Quick actions: "Tmux" (if channel available), "Pause", "Shutdown", "Close"

---

## Kill Switch (global session control state machine)

Defined in `DashboardSessionControlHandlers`, accessible from elsewhere in the dashboard. Three-step confirmation (`kill_switch_click` -> `kill_switch_first_confirm` -> `kill_switch_second_confirm`). On second confirmation emits `:mesh_pause` signal with `initiated_by: "god_mode"`, pausing the entire mesh. Cancel resets state at any step.

---

## Push Instructions (global broadcast)

Also in `DashboardSessionControlHandlers`. Events: `push_instructions_intent` (sets pending confirmation with `agent_class`), `push_instructions_confirm` (emits `:agent_instructions` signal with class + instructions text), `push_instructions_cancel`. Not visible in the fleet template itself but shares the same handler module.

---

## Essential Files

- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/command_components/command_view.html.heex` -- the entire fleet page template
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/command_components.ex` -- component module, `fleet_status_bar` component, helper functions for rendering
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/fleet_helpers.ex` -- pure helpers: role classification, hierarchy sorting, chain-of-command, comms filtering, name resolution
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_fleet_tree_handlers.ex` -- `toggle_fleet_team`, `set_comms_filter`, `trace_agent`, `clear_trace`
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_session_control_handlers.ex` -- pause, resume, shutdown, HITL approve/reject, kill switch, push instructions
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_dag_handlers.ex` -- `select_command_agent`, `send_command_message`, `clear_command_selection`
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_messaging_handlers.ex` -- `send_targeted_message`, `set_message_target`, mailbox subscription and message receipt
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_tmux_handlers.ex` -- `launch_session`
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_state.ex` -- `recompute/1` (all data queries), `default_assigns/1` (initial assign shape)
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_info_handlers.ex` -- signal dispatch, debounced recompute, HITL gate refresh
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_live.ex` -- root LiveView, event routing, URL param parsing
