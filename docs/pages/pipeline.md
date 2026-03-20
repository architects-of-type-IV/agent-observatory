Let me systematically find and read all relevant files for the pipeline/default page.
Now let me read the Projects.Runtime and Graph to understand the data source, plus the header fleet status bar and sidebar components.
Now let me check the fleet status bar, sidebar components, and filter/info handlers to complete the picture.
Now let me look at the filter handlers and info handlers to understand the PubSub updates.
Now I have a complete picture. Let me compile the full analysis.

---

## Complete Feature Analysis: /pipeline (Default Page)

### Overview

The `/pipeline` view is the default landing page of the ICHOR IV dashboard. It is a real-time task pipeline board backed by `tasks.jsonl` files auto-discovered from active agent working directories. The URL path `/` (or any unrecognized `?view=` param) resolves to `nav_view: :pipeline`.

---

### Layout Structure

The page is composed of three zones shared across all dashboard views, plus a pipeline-specific content area:

1. **Sticky Header** (global, always visible)
2. **Left Vertical Nav Bar** (global icon navigation)
3. **Pipeline Content Area** (pipeline-specific, rendered when `@nav_view == :pipeline`)
4. **Right Sidebar** (collapsible, teams/sessions/tmux/message composer)
5. **Bottom Detail Drawer** (conditional, when a task/event/agent is selected)
6. **Global Overlays** (tmux multi-panel, agent slideout, Archon overlay, shortcuts modal, toast stack)

---

### Zone 1: Sticky Header

File: `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_live.html.heex` (lines 16-184)

#### Branding + Live Indicator
- "ICHOR IV" wordmark
- Animated green pulse dot with "live" label (always on, CSS animation)

#### Fleet Status Bar
Component: `IchorWeb.Components.CommandComponents.fleet_status_bar`
File: `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/command_components.ex` (lines 26-134)

Displays the following counters, all with hover tooltips:
- Total agents: broken down into active (`a`), idle (`i`), ended (`e`) counts, color-coded
- Error count (red dot + count when > 0)
- Message count (mailbox messages)
- Tool call count (total tool calls from events)
- Visible/total events ratio
- Task progress bar (done/total with percentage) from `active_tasks`
- Pipeline progress bar (completed/total in cyan) from `dag_state.pipeline`, shown only when different from task bar
- Health badge: green "OK" or red with issue count, derived from `dag_state.health` and error count
- Protocol stats: traces (T:), mailbox pending (M:), command queue (Q:) -- shown only when non-zero

Data sources: `@agent_index` (map of all agents), `@active_tasks`, `@dag_state`, `@errors`, `@messages`, `@protocol_stats`, `@visible_events`

#### Search Bar
- Free-text search input, phx-change `search_feed`, debounce 150ms
- Searches across tool name, command, file, message, team

#### Filter Dropdowns
- "All Apps" select: filters by `source_app` (unique values from events), phx-change `filter`
- "All Events" select: filters by `hook_event_type`, phx-change `filter`

#### Preset Buttons
- **Failed** (red): applies `apply_preset` with `failed_tools` -- filters to failed tool calls
- **Teams** (cyan): applies `team_events` preset
- **Slow** (brand): applies `slow` preset -- filters to slow events
- **Errors** (red): applies `errors_only` preset
- **Reset** (interactive, conditional): shown only when any filter is active, clears all filters via `clear_filters` + JS `selectedIndex` reset

#### Action Buttons
- **Export** dropdown: JS-powered dropdown (phx-hook `ExportDropdown`)
  - JSON download link: `/export?session=...&q=...&event_type=...&format=json`
  - CSV download link: same with `format=csv`
- **Clear**: clears all events via `clear_events`
- **?**: toggles keyboard shortcuts help modal via `toggle_shortcuts_help`

---

### Zone 2: Left Navigation

File: `dashboard_live.html.heex` (lines 189-314)

Five nav icons (SVG), each a `<.link patch=...>`, with active state highlight:
- **Pipeline** (`/`) -- columns/kanban SVG, active when `@nav_view == :pipeline`
- **Fleet Control** (`/fleet`) -- group/people SVG
- **Workshop** (`/workshop`) -- wrench SVG
- **Signals** (`/signals`) -- wifi/radio SVG
- **MES** (`/mes`) -- flask/beaker SVG

Bottom utility links (open in new tab):
- **LiveDashboard** (`/dev/dashboard`)
- **Mailbox** (`/dev/mailbox`)
- **MCP API** (`/mcp`)

All icons have `ichor-tip ichor-tip-right` tooltips.

---

### Zone 3: Pipeline Content Area

Rendered when `@nav_view == :pipeline`. Consists of:

#### Pipeline Header Bar
File: `dashboard_live.html.heex` (lines 332-363)

- "Pipeline Board" label (uppercase, muted)
- Status summary badge row (shown when `@dag_state.pipeline.total > 0`):
  - Green: N done
  - Blue: N running
  - Default: N pending
  - Brand/orange: N blocked (conditional, shown when > 0)
  - Red: N failed (conditional, shown when > 0)

#### Pipeline View Component
Component: `IchorWeb.Components.PipelineComponents.pipeline_view`
Files:
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/pipeline_components.ex`
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/pipeline_components/pipeline_view.html.heex`
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/pipeline_components/dag_node.html.heex`

Props received: `@dag_state`, `@selected_dag_task`, `@show_add_project`, `@now`

**Two-column layout:**

##### Left Panel (240px fixed): Projects + Task Detail

Projects Section:
- Badge list of all watched project keys (font-mono, zinc style)
- "Auto-detecting..." placeholder when no projects
- Action buttons:
  - **GC** (danger, with confirm dialog): `trigger_dag_gc` -- archives completed work for active project
  - **Health** (muted): `run_dag_health_check` -- triggers immediate health check via shell script
  - **Reset Stale** (brand): `reset_dag_stale` -- resets all in-progress tasks stale > 10 minutes back to pending

Selected Task Detail Card (conditional, shown when `@selected_dag_task` is set):
- Task metadata: project key (violet, monospace), task ID (#N monospace), status badge (color-coded), priority label
- Subject text
- Description text (if present)
- Owner (if present)
- Blocked-by task IDs (if non-empty)
- Updated timestamp (short time HH:MM:SS)
- Action buttons:
  - **Unassign**: `reassign_dag_task` with empty owner
  - **Reset**: `heal_dag_task` -- resets task status back to pending

##### Right Panel (flex-1): Kanban Board + DAG Graph

**Empty State:** When no tasks exist, shows "No pipeline active" with description "Projects with tasks.jsonl are auto-detected from session events."

**Kanban Board** (auto-fit grid, min 140px columns):
Five columns, each shown only when non-empty:
- **Blocked** (brand/orange border)
- **Pending** (subtle border)
- **In Progress** (info/blue border)
- **Done** (success/green border)
- **Failed** (error/red border)

Each column:
- Header with label + count
- Scrollable card list (max-height 280px)

Each task card:
- Click to select: `select_dag_node` with task ID (toggle: clicking selected task deselects)
- Project key (violet/60, 9px monospace, if present)
- Task ID (9px monospace, muted)
- Priority label (color-coded: critical=error, high=brand, medium=default, low=muted)
- Subject text (10px, 2-line clamp)
- Owner (9px monospace, shown when non-empty)
- Blocked-by IDs (shown when non-empty, brand label)
- Selected state: ring highlight (`!ring-1 !ring-interactive/50 !bg-raised/60`)

**DAG Dependency Graph** (shown when `dag.waves != []`):
- Section header "Dependency Graph" with critical path task count
- Horizontal scrollable wave layout
- Each wave labeled "Wave 0", "Wave 1", etc.
- Each task in a wave rendered as a `<.dag_node>` button:
  - Click: `select_dag_node` (same toggle behavior as kanban)
  - Task ID (#N monospace)
  - Status dot (color + animation): completed=green, in_progress=blue+pulse, failed=red, pending=low/grey, other=highlight
  - Subject text (truncated, max 120px)
  - Owner (10px monospace, muted, shown when non-empty)
  - Border styling driven by status + critical path membership + selected state:
    - Critical path tasks get ring highlight
    - Selected tasks get interactive border
    - Completed: green border (critical path gets stronger ring)
    - In progress: info/blue border
    - Failed: error/red border
  - Background: completed=success/5, in_progress=info/5, failed=error/5, other=base/50
  - Missing task (ID in wave but not in task_map): grey "missing" placeholder

---

### Zone 4: Right Sidebar (Collapsible)

Toggle button between content and sidebar: `toggle_sidebar` event, collapses to `w-0 overflow-hidden`.

File: `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/sidebar_components.ex`

**Teams Section** (shown when `@teams != []`):
- "Teams (N)" header
- Each team item:
  - Click: `select_team` with team name
  - Team name + member count
  - Task progress bar (done/total + percentage bar) if team has tasks
  - Member list: each with status dot (active/idle/ended), name, agent type
  - **Ping** button: `send_team_broadcast` with `content: "status"` -- broadcasts status request to all team agents

**Sessions Section** (or "Standalone" when teams exist):
- "Sessions (N/total)" or "Standalone (N)" header
- Session search input: `search_sessions`, debounce 150ms
- Each session item:
  - Click: `filter_session` with session_id (filters event feed to that session)
  - Color dot (unique color per session ID, faded when ended)
  - Source app name + short session ID
  - Model badge
  - Event count + duration + abbreviated CWD

**Tmux Section** (shown when `@tmux_sessions != []`):
- "Tmux (N)" header
- Each tmux session:
  - Green dot if registered to an agent, yellow "orphan" dot if unmatched
  - Session name (monospace)
  - Hover reveals two buttons: **tty** (`connect_tmux`) and **kill** (`kill_sidebar_tmux`)

**Message Composer** (shown when `@teams != []`):
- Below sessions section
- `phx-update="ignore"` wrapper with `ClearFormOnSubmit` hook (stable DOM, prevents timer-driven clears)
- `IchorWeb.Components.TeamMessageComponents.message_composer` -- allows broadcasting a message to a team

---

### Zone 5: Bottom Detail Drawer

Shown when any of `@selected_event`, `@selected_task`, or `@selected_agent` is set. Max height 40vh, scrollable.

Component: `IchorWeb.Components.DetailPanelComponents.detail_panel`
File: `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/detail_panel_components/detail_panel.html.heex`

Receives: selected event/task/agent, all events, active tasks, event notes, expanded events, now.

---

### Zone 6: Global Overlays (always in DOM)

#### Tmux Multi-Panel
Shown when `@tmux_panels != []`. Full-screen backdrop with stopPropagation interior.

Features:
- Tab list of open sessions (brand-highlighted active tab, success dot)
- Tab count badge
- **Tile/Tabs** toggle: `toggle_tmux_layout` -- switches between single-active-pane and CSS grid of all panes
- **Kill** button (active session): `kill_tmux_session` with confirm dialog
- **Close Tab**: `disconnect_tmux`
- **x**: `close_all_tmux`
- Terminal output rendered as ANSI-to-HTML via `AnsiUtils.to_html/1`
- Tiled layout: responsive 2-column grid (1 col for 1-2 sessions, 2 col for 3+), click any tile to activate
- Input bar (active session only): `send_tmux_keys` form, stable DOM with `phx-update="ignore"`

#### Agent Slideout
Shown when `@agent_slideout` is set (`open_agent_slideout` event). 480px right drawer with backdrop.

Sections:
- Header: status dot, agent short name, first 12 chars of session ID, close button
- Agent info grid (2-col DL): status, role, team, CWD basename, channels list
- Terminal output: ANSI-rendered, scrollable (max 40vh), char count, "No terminal output captured" empty state
- Activity feed: last 50 items, each with type dot (cyan=event, violet=other), content, HH:MM:SS timestamp
- Quick actions: **Tmux** button (shown when tmux channel exists), **Pause**, **Shutdown**, **Close**

#### Shortcuts Modal
`IchorWeb.Components.ModalComponents.shortcuts_modal`, toggled by `toggle_shortcuts_help`.

#### Archon FAB + Overlay
- FAB: `archon_toggle` event, always visible bottom-right
- Overlay (shown when `@show_archon`): tabs (command/chat/ref), messages list, loading state, snapshot, attention items
- Events: `archon_send`, `archon_close`, `archon_set_tab`, `archon_shortcode`

#### Toast Stack
`IchorWeb.Components.ArchonComponents.Toast.toast_stack` with `@toasts` list. `dismiss_toast` event to remove individual toasts. Also a hidden `Toast` hook container for JS-emitted toasts.

#### Browser Notifications
Hidden `<div id="browser-notifications" phx-hook="BrowserNotifications">` -- pushes OS notifications.

#### Keyboard Shortcuts Hook
`phx-hook="KeyboardShortcuts"` on root div, dispatches `keyboard_escape`, `keyboard_navigate`, `toggle_shortcuts_help`.

---

### Data Sources

| Data | Source | Update Mechanism |
|---|---|---|
| `dag_state` | `Ichor.Projects.Runtime` GenServer (ETS-backed poll every 3s) | Signal `:dag_status` broadcast received by `DashboardInfoHandlers.dispatch/2`, assigns `dag_state` |
| `tasks` | Parsed from `tasks.jsonl` in each watched project directory | Polled every 3s; also triggered by new agent events (CWD registration) |
| Watched projects | Auto-discovered from: event CWD buffer, `~/.claude/teams/` config.json files, `~/.claude/teams/.archive/` | Re-scanned on every `:poll_tasks` cycle |
| DAG structure | Computed by `Ichor.Projects.Graph` (pure functions): topological sort into waves, critical path (longest chain), edge list | Recomputed on every task refresh |
| Pipeline stats | `Graph.pipeline_stats/1` | Same |
| `teams` | `Ichor.Control.Team.alive!()` (Ash query) | `recompute/1` on signals: `agent_spawned`, `agent_stopped`, `registry_changed`, `fleet_changed` |
| `sessions` | Derived by `FQ.active_sessions/2` from events + tmux | Same recompute |
| `agents` / `agent_index` | `Ichor.Control.Agent.all!()` (Ash query) | Same recompute |
| `errors` | `Ichor.Observability.Error.recent!()` | Same recompute |
| `messages` | `Ichor.Observability.Message.recent!()` + `Bus.recent_messages/1` | Same recompute |
| Health | `~/.claude/skills/swarm/scripts/health-check.sh` shell script | Polled every 30s, or on-demand via `run_dag_health_check` button |

---

### Event Handlers (Pipeline-Relevant)

All are dispatched through `DashboardDagHandlers.dispatch/3`:

| Event | Handler | Effect |
|---|---|---|
| `select_dag_node` | `handle_select_dag_node/2` | Toggles `selected_dag_task` assign (deselects if already selected) |
| `heal_dag_task` / `heal_task` | `handle_heal_task/2` | `Runtime.heal_task(id)` -- resets task to pending via `JsonlStore` |
| `reassign_dag_task` | `handle_reassign_dag_task/2` | `Runtime.reassign_task(id, owner)` -- writes new owner to `tasks.jsonl` |
| `reset_dag_stale` | `handle_reset_all_stale/2` | Resets all in-progress tasks stale > 10 min |
| `run_dag_health_check` | `handle_run_health_check/2` | Runs health check script immediately |
| `trigger_dag_gc` | `handle_trigger_gc/2` | Archives completed tasks for the active project |
| `claim_dag_task` | `handle_claim_dag_task/2` | Sets task to in_progress with agent name |
| `select_dag_project` | `handle_select_project/2` | Switches active project in Runtime GenServer |

All mutations in `Runtime` write to `tasks.jsonl` via `Ichor.Tasks.JsonlStore`, then call `refresh_tasks/1` and broadcast `:dag_status` signal, which the LiveView receives and assigns to `@dag_state`.

---

### Real-Time Update Flow

1. `Ichor.Projects.Runtime` polls `tasks.jsonl` every 3 seconds (`@tasks_poll_interval 3_000`)
2. On change: emits `Ichor.Signals.emit(:dag_status, %{state_map: state})`
3. `DashboardLive` subscribed to all signal categories at mount
4. `handle_info(%Message{name: :dag_status, ...}, socket)` in `DashboardInfoHandlers` assigns new `dag_state`
5. Template re-renders kanban, DAG graph, and header stats reactively

---

### Key Files

| File | Role |
|---|---|
| `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_live.ex` | Root LiveView, event routing |
| `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_live.html.heex` | Root template: header, nav, view dispatch, sidebar, overlays |
| `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/pipeline_components/pipeline_view.html.heex` | Kanban board + DAG graph layout |
| `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/pipeline_components/dag_node.html.heex` | Single DAG node button |
| `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/pipeline_components.ex` | Pipeline component module + styling helpers |
| `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_dag_handlers.ex` | DAG event handler dispatch |
| `/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/runtime.ex` | Runtime GenServer: discovery, polling, task mutations, health checks |
| `/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/graph.ex` | Pure DAG computation: waves, edges, critical path, stats |
| `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_state.ex` | `recompute/1` -- derives all dashboard assigns from Ash queries |
| `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/sidebar_components.ex` | Right sidebar: teams, sessions, tmux, message composer |
| `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/command_components.ex` | `fleet_status_bar` header widget |
| `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_view_router.ex` | URL param to nav_view atom mapping |
