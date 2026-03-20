Let me find and read all relevant files for the /signals page.
Now let me read the feed handlers, the signal runtime, and the renderer primitives/domain renderers:
Now let me read the signal runtime and the handlers that feed the stream:
Now let me check the stream events (search, filter, pause, clear) handlers:
Now let me check the nav link in the dashboard template for the signals icon:
I now have a complete picture of the /signals page. Here is a comprehensive feature description.

---

## /signals Page - Complete Feature Description

### Overview

The /signals page is the "nervous system" view of the ICHOR dashboard. It is a full-height, two-panel layout that exposes every internal event fired across the ICHOR system in real time. It is reached via URL `/signals` (or `/?view=signals`) and is rendered when `@nav_view == :signals`.

---

### Layout

The page is a fixed-height flex container with two side-by-side panels, mounted in the main dashboard live view at route `/signals`.

- Left panel: fixed width 320px, scrollable, sticky header -- the Signal Catalog
- Right panel: flex-fill, overflow-hidden column -- the Live Feed

---

### Panel 1: Signal Catalog

**Location:** `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_components.ex`, lines 27-66.

**Data source:** `Ichor.Signals.Catalog.all/0` and `Ichor.Signals.Catalog.categories/0` -- both compile-time computed from the catalog definition in `/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/catalog.ex`.

**UI elements:**
- Sticky header showing the total count of signals and total count of categories (e.g. "87 signals across 13 categories").
- One section per category, each with a colored category label (using `category_color/1` which maps category atoms to Tailwind color tokens).
- Within each section, one row per signal showing:
  - A "dyn" badge (brand color, `text-[8px]`) if the signal is marked `dynamic: true` in the catalog.
  - The signal name rendered as a clickable button in monospace interactive color.
  - The signal's `doc` string (description).
  - The signal's `keys` list joined by commas in parentheses, shown in smaller monospace font.

**Interaction:** Clicking any signal name fires `phx-click="stream_filter_topic"` with `phx-value-topic` set to `"category:signal_name"` (e.g. `"fleet:agent_started"`). This immediately filters the live feed to show only signals matching that topic string and resets the stream to the last 200 matching entries from the buffer.

**Category color mapping:**
- `:events` - success (green)
- `:fleet` - brand (blue/brand)
- `:gateway` - cyan
- `:agent` - interactive (blue)
- `:hitl` - error (red)
- `:mesh` - brand
- `:team` - info
- `:monitoring` - default
- `:messages` - success
- `:memory` - interactive
- `:system` - muted
- `:genesis` - brand
- `:dag` - info
- `:mes` - default
- Unknown - muted

---

### Panel 2: Live Feed

**Location:** `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_components.ex`, lines 68-146.

**Header bar (sticky, blur backdrop):**
- "Live Feed" label
- Filter text input (phx-change="stream_search", debounce 100ms, placeholder "Filter by signal, category, or content...")
- Pause/Resume toggle button (phx-click="stream_toggle_pause") - shows "Paused" with brand highlight when paused, "Pause" in normal state
- Clear button (phx-click="stream_clear") - clears entire feed and resets filter to empty

**Feed table:**
- `id="stream-feed"` with `phx-hook="StreamAutoScroll"` (JavaScript hook that auto-scrolls to newest entries)
- Sticky header row with columns: Time (70px), Category (80px), Signal (120px), Detail (flex)
- Body element `id="signals"` uses `phx-update="stream"` (Phoenix LiveView streaming, prepends new rows at top)

**Each row:**
- `id` is `"signal-{seq}"` where seq is the monotonic integer sequence from the buffer
- Row background highlights:
  - `bg-error/5` for: `agent_crashed`, `schema_violation`, `dead_letter`
  - `bg-brand/5` for: `nudge_warning`, `nudge_sent`, `nudge_escalated`, `nudge_zombie`
  - `bg-info/5` for: `gate_passed`, `gate_failed`
  - No highlight for all other signals
- Time column: wall-clock timestamp in `HH:MM:SS` format, computed from monotonic milliseconds via `System.time_offset`
- Category column: domain atom rendered with category color
- Signal column: signal name as a clickable button -- clicking fires `stream_filter_topic` with `"domain:name"` as the topic, filtering the feed to that specific signal type
- Detail column: rendered by the per-domain renderer (see below)

**Paused state indicator:** When the feed is paused, a centered "Feed paused" message is shown at the bottom of the scroll area.

---

### Data Pipeline

**Source of truth:** `Ichor.Signals.Catalog` - a compile-time map of ~87 signal definitions across 13 categories, defined in `/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/catalog.ex`.

**Emission:** Any system component calls `Ichor.Signals.emit(name, data)` or `Ichor.Signals.emit(name, scope_id, data)` (for dynamic/scoped signals). The runtime (`/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/runtime.ex`) validates the signal against the catalog, builds a `%Message{}` struct with a monotonic timestamp, and broadcasts to Phoenix.PubSub on topic `"signals:{category}"` (for category-level subscriptions) and `"signals:{category}:{name}"` (for per-signal subscriptions). Dynamic signals also broadcast on `"signals:{category}:{name}:{scope_id}"`.

**Buffer:** `Ichor.Signals.Buffer` (`/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/buffer.ex`) is a supervised GenServer that:
- Subscribes to all signal category PubSub topics at startup
- Stores each incoming `%Message{}` in an ETS table named `:signal_buffer`, keyed by a monotonic sequence integer
- Evicts entries beyond the last 200 (ring buffer, max 200 events)
- Re-broadcasts each signal on `"signals:feed"` as `{:signal, seq, %Message{}}` for the LiveView

**LiveView subscription:** When the user navigates to `:signals`, `apply_nav_view(:signals, socket)` subscribes the LiveView process to `"signals:feed"`. It also initializes the Phoenix stream `:signals` (if not already present) with `dom_id: fn {seq, _msg} -> "signal-#{seq}" end` and pre-loads the stream with `Buffer.recent(200)`.

**Real-time updates:** `handle_info({:signal, seq, %Message{}}, socket)` in `DashboardLive`:
1. If `stream_paused` is true, drops the message entirely (no socket update).
2. If the message does not pass `passes_filter?/2`, drops it.
3. Otherwise, calls `stream_insert(socket, :signals, {seq, message}, at: 0, limit: 200)` -- inserts at the top, capped at 200 rows.

Additionally, the dashboard subscribes to all signal categories globally at mount (`Enum.each(Catalog.categories(), &Ichor.Signals.subscribe/1)`) for its other panels; the signals page uses the separate `"signals:feed"` re-broadcast from the Buffer.

---

### User Interactions and Events

| Event | Trigger | Handler | Effect |
|---|---|---|---|
| `stream_search` | Typing in filter input (debounced 100ms) | `DashboardLive.handle_event/3` | Assigns new `stream_filter`, resets stream to filtered buffer snapshot |
| `stream_toggle_pause` | Pause/Resume button | `DashboardLive.handle_event/3` | Toggles `stream_paused` boolean |
| `stream_clear` | Clear button | `DashboardLive.handle_event/3` | Resets `stream_filter` to `""`, resets stream to empty |
| `stream_filter_topic` | Click signal name in catalog or in feed rows | `DashboardLive.handle_event/3` | Sets `stream_filter` to `"category:name"`, resets stream to filtered buffer snapshot |

**Filter logic** (`passes_filter?/2` and `signal_matches?/2`): case-insensitive substring match against `domain`, `name`, and `"domain:name"` combined string. Does not search payload/data content.

---

### Signal Domains and Renderer Dispatch

The `IchorWeb.SignalFeed.Renderer` (`/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_feed/renderer.ex`) dispatches to one of 8 domain-specific renderer modules based on `message.domain`:

| Domains | Renderer Module |
|---|---|
| `:agent`, `:fleet` | `Renderers.Agent` |
| `:system`, `:events`, `:messages`, `:memory` | `Renderers.Core` |
| `:gateway`, `:hitl`, `:mesh` | `Renderers.Gateway` |
| `:genesis` | `Renderers.Genesis` |
| `:dag` | `Renderers.Dag` |
| `:mes` | `Renderers.Mes` |
| `:monitoring`, `:team` | `Renderers.Monitoring` |
| anything else | `Renderers.Fallback` |

Each renderer has explicit per-signal-name `render/1` clauses for known signals, and a catch-all clause that renders the signal name plus all data key-value pairs as badges. The fallback renderer displays `"domain:name"` plus all data fields.

**Rendering primitives** (`/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_feed/primitives.ex`):
- `kv/1` - monospace `key: value` badge with surface-raised background
- `label/1` - colored text label chip
- `ts/1` - HH:MM:SS timestamp from monotonic ms
- `id_short/1` - truncates IDs to first 8 characters

---

### Complete Signal Catalog (87 signals across 13 categories)

**fleet (8):** `agent_started`, `agent_paused`, `agent_resumed`, `agent_stopped`, `team_created`, `team_disbanded`, `hosts_changed`, `fleet_changed`, `agent_evicted`, `agent_reaped`, `agent_discovered`

**system (3):** `heartbeat`, `registry_changed`, `dashboard_command`

**events (1):** `new_event`

**messages (1):** `message_delivered`

**memory (2):** `block_changed`, `memory_changed` (dynamic)

**team (4):** `task_created` (dynamic), `task_updated` (dynamic), `task_deleted` (dynamic), `tasks_updated`

**monitoring (5):** `protocol_update`, `gate_passed`, `gate_failed`, `agent_done`, `agent_blocked`, `watchdog_sweep`

**gateway (9):** `decision_log`, `schema_violation`, `node_state_update`, `entropy_alert`, `topology_snapshot`, `capability_update`, `dead_letter`, `gateway_audit`, `mesh_pause`, `cron_job_scheduled`, `cron_job_rescheduled`

**agent (11):** `agent_crashed`, `nudge_warning`, `nudge_sent`, `nudge_escalated`, `nudge_zombie`, `agent_spawned`, `agent_event` (dynamic), `agent_message_intercepted` (dynamic), `terminal_output` (dynamic), `mailbox_message` (dynamic), `agent_instructions` (dynamic), `scheduled_job` (dynamic)

**hitl (5):** `gate_open` (dynamic), `gate_close` (dynamic), `hitl_auto_released`, `hitl_operator_approved`, `hitl_operator_rejected`

**mesh (1):** `dag_delta` (dynamic)

**mes (30+):** Full MES scheduler/run/team/janitor/quality gate/tmux/agent/project/research/DAG lifecycle signals

**genesis (9):** `genesis_team_ready`, `genesis_team_spawn_failed`, `genesis_team_killed`, `genesis_run_init`, `genesis_tmux_gone`, `genesis_run_complete`, `genesis_run_terminated`, `genesis_node_created`, `genesis_node_advanced`, `genesis_artifact_created`

**dag (9):** `dag_run_created`, `dag_run_ready`, `dag_run_completed`, `dag_run_archived`, `dag_job_claimed`, `dag_job_completed`, `dag_job_failed`, `dag_job_reset`, `dag_tmux_gone`, `dag_health_report`, `dag_status`

---

### State Assigns Used

- `@streams.signals` - Phoenix stream of `{seq, %Message{}}` tuples
- `@stream_filter` - current filter string (default `""`)
- `@stream_paused` - boolean pause state (default `false`)
- `@nav_view` - `:signals` when on this page

---

### Key Files

- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_components.ex` - main template for both panels
- `/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/catalog.ex` - all 87+ signal definitions, source of truth for catalog panel
- `/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/buffer.ex` - ETS ring buffer + PubSub re-broadcaster (max 200 events)
- `/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/runtime.ex` - emit/subscribe/unsubscribe transport layer
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_live.ex` - LiveView mount, `apply_nav_view(:signals)`, stream event handlers (`stream_search`, `stream_toggle_pause`, `stream_clear`, `stream_filter_topic`), `passes_filter?/2`
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_feed/renderer.ex` - domain dispatch router
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_feed/primitives.ex` - shared kv/label/ts/id_short micro-components
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_feed/renderers/agent.ex` - agent + fleet domain renderer
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_feed/renderers/core.ex` - system/events/messages/memory renderer
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_feed/renderers/gateway.ex` - gateway/hitl/mesh renderer
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_feed/renderers/monitoring.ex` - monitoring/team renderer
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_feed/renderers/dag.ex` - dag domain renderer
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_feed/renderers/genesis.ex` - genesis domain renderer
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_feed/renderers/mes.ex` - mes domain renderer
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_feed/renderers/fallback.ex` - catch-all renderer
