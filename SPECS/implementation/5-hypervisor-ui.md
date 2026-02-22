---
type: phase
id: 5
title: hypervisor-ui
date: 2026-02-22
status: pending
links:
  adr: [ADR-022]
depends_on:
  - phase: 1
  - phase: 2
  - phase: 3
  - phase: 4
---

# Phase 5: Hypervisor UI

## Overview

This phase builds the six-view LiveView shell that replaces the existing seven-tab Observatory dashboard navigation. Each of the six views — Fleet Command, Session Cluster, Registry, Scheduler, Forensic Inspector, and God Mode — answers a distinct operational question about the agent mesh and is rendered by a dedicated component module. No existing component module is deleted; all previous views (Feed, Messages, Tasks, Protocols, Analytics, Timeline, Errors) are absorbed as collapsible sub-panels within the new architecture. Navigation is entirely keyboard-driven (keys `1`–`6` for view selection, `Escape` for drill-down dismissal and fallback to Fleet Command), with `view_mode` persisted to localStorage and recovered gracefully on mount.

The new LiveView shell is introduced by extending the existing `ObservatoryWeb.DashboardLive` module with six `view_mode` atoms (`:fleet_command`, `:session_cluster`, `:registry`, `:scheduler`, `:forensic`, `:god_mode`) and wiring a `render/1` dispatch table that delegates to the corresponding component module. Legacy atoms stored in localStorage from previous sessions resolve to `:fleet_command` via a client-side guard and a server-side catch-all handler with a warning log. God Mode introduces an elevated-risk danger-zone styling contract enforced via dedicated CSS classes and a double-confirmation kill-switch state machine tracked in socket assigns.

### ADR Links
- [ADR-022](../decisions/ADR-022-six-view-ui-architecture.md) — Six-View UI Information Architecture: defines the six Hypervisor views, their keyboard shortcuts, dedicated component module names, migration from the existing seven-tab navigation, and the danger-zone styling and double-confirm requirements for God Mode.

---

## 5.1 Six-View Navigation Shell

- [ ] **Section 5.1 Complete**

This section wires the top-level navigation shell into `ObservatoryWeb.DashboardLive`: the six valid `view_mode` atoms with a `:fleet_command` default, keyboard shortcuts `1`–`6` and `Escape` via `phx-window-keydown`, localStorage persistence and recovery including graceful handling of legacy atom strings, and a `render/1` dispatch table that delegates to the six dedicated component modules. It covers FR-12.1 (six atoms and default), FR-12.2 (keyboard shortcuts), FR-12.3 (Escape key), and FR-12.4 (localStorage mismatch recovery), producing the compilable navigation foundation that all view-specific sections build on.

### 5.1.1 Six view_mode Atoms, Default Assign, and localStorage Hook

- [ ] **Task 5.1.1 Complete**
- **Governed by:** ADR-022
- **Parent UCs:** UC-0300, UC-0301, UC-0303

Define the six valid `view_mode` atoms as a module attribute on `ObservatoryWeb.DashboardLive`, assign `view_mode: :fleet_command` as the initial socket assign in `mount/3`, and implement the client-side JavaScript hook and server-side `handle_event("restore_view_mode", ...)` handler for localStorage persistence and recovery. The hook must validate the stored string against the valid set and either push `"fleet_command"` or not push at all for unrecognized values. The server-side handler must include a catch-all clause that assigns `view_mode: :fleet_command` and emits a `Logger.warning/1` entry when an unrecognized atom is received.

- [ ] 5.1.1.1 In `lib/observatory_web/live/dashboard_live.ex`, add `@valid_view_modes ~w(fleet_command session_cluster registry scheduler forensic god_mode)a` as a module attribute; in `mount/3`, add `|> assign(:view_mode, :fleet_command)` before the `prepare_assigns/1` call `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.1.1.2 In `assets/js/app.js` (or the appropriate hooks file), add a `ViewModePersistence` hook with an `mounted()` callback that reads localStorage key `"view_mode"`, validates it against the set `["fleet_command", "session_cluster", "registry", "scheduler", "forensic", "god_mode"]` inside a `try/catch`, and pushes `{event: "restore_view_mode", payload: {value: storedValue}}` to the LiveView only when the value is in the valid set; registers the hook in the LiveSocket hooks map `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.1.1.3 In `lib/observatory_web/live/dashboard_navigation_handlers.ex`, add `def handle_event("restore_view_mode", %{"value" => value}, socket)` with a case clause matching each of the six valid string values to their corresponding atom (e.g., `"fleet_command" -> :fleet_command`), calling `assign(socket, :view_mode, atom)` and writing the value to localStorage via `push_event`; add a catch-all clause `_ ->` that calls `Logger.warning("Unrecognized view_mode: #{inspect(value)}")` and assigns `view_mode: :fleet_command` `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.1.1.4 Write `mix test test/observatory_web/live/dashboard_live_test.exs` tests asserting: (a) DashboardLive mounts with `socket.assigns.view_mode == :fleet_command` before any client events; (b) pushing `restore_view_mode` with `"scheduler"` updates `view_mode` to `:scheduler`; (c) pushing `restore_view_mode` with legacy value `"command"` results in `view_mode: :fleet_command` and emits a warning log; (d) pushing `restore_view_mode` with each of the eight legacy atoms (`"pipeline"`, `"agents"`, `"protocols"`, `"feed"`, `"errors"`, `"analytics"`, `"timeline"`, `"command"`) all result in `view_mode: :fleet_command` without raising `done_when: "mix test test/observatory_web/live/dashboard_live_test.exs"`

### 5.1.2 Keyboard Shortcuts 1–6 and Escape Key Handler

- [ ] **Task 5.1.2 Complete**
- **Governed by:** ADR-022
- **Parent UCs:** UC-0301, UC-0302

Implement the `handle_event("keydown", ...)` handler in `lib/observatory_web/live/dashboard_navigation_handlers.ex` that maps keys `"1"`–`"6"` to the six `view_mode` atoms and key `"Escape"` to either drill-down dismissal or Fleet Command fallback. The Escape handler must inspect `selected_session_id`, `inspected_agent_id`, and `drill_down_open` assigns in priority order: if any is non-nil/true, clear it without changing `view_mode`; else if `view_mode != :fleet_command`, assign `:fleet_command` and persist to localStorage; else return the socket unchanged. Keys outside `"1"`–`"6"` and `"Escape"` must be no-ops handled by a catch-all clause.

- [ ] 5.1.2.1 In `lib/observatory_web/live/dashboard_navigation_handlers.ex`, add the following keydown clauses: `"1" -> assign(socket, :view_mode, :fleet_command)`, `"2" -> :session_cluster`, `"3" -> :registry`, `"4" -> :scheduler`, `"5" -> :forensic`, `"6" -> :god_mode`; each clause must also call `push_event(socket, "persist_view_mode", %{value: to_string(atom)})` to write localStorage; add a catch-all `_, socket -> {:noreply, socket}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.1.2.2 In `lib/observatory_web/live/dashboard_navigation_handlers.ex`, implement the `"Escape"` clause: `cond do assigns.selected_session_id != nil -> assign(socket, :selected_session_id, nil); assigns.inspected_agent_id != nil -> assign(socket, :inspected_agent_id, nil); assigns.drill_down_open -> assign(socket, :drill_down_open, false); assigns.view_mode != :fleet_command -> assign(socket, :view_mode, :fleet_command) |> push_event("persist_view_mode", %{value: "fleet_command"}); true -> socket end`; initialize `drill_down_open: false`, `selected_session_id: nil`, `inspected_agent_id: nil` in `mount/3` if not already present `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.1.2.3 Write tests in `test/observatory_web/live/dashboard_live_test.exs` asserting: (a) simulated `keydown` events for keys `"1"` through `"6"` each transition `view_mode` to the correct atom; (b) `keydown` with `"7"` leaves `view_mode` unchanged; (c) `keydown` `"Escape"` with `selected_session_id` set to `"sess-abc"` clears `selected_session_id` to nil while `view_mode` is unchanged; (d) `keydown` `"Escape"` on `:forensic` with no drill-down sets `view_mode` to `:fleet_command`; (e) `keydown` `"Escape"` on `:fleet_command` with no drill-down produces no socket assign changes `done_when: "mix test test/observatory_web/live/dashboard_live_test.exs"`

### 5.1.3 render/1 Dispatch Table and Six Component Module Stubs

- [ ] **Task 5.1.3 Complete**
- **Governed by:** ADR-022
- **Parent UCs:** UC-0304

Implement the `render/1` dispatch table in `lib/observatory_web/live/dashboard_live.html.heex` (or as a `render/1` function head in `dashboard_live.ex`) that pattern-matches on `view_mode` and delegates to the six dedicated component modules. Create stub implementations for all six component modules at their canonical file paths so the dispatch table compiles without `UndefinedFunctionError`. Each stub must expose the primary public function component that accepts socket assigns and renders a minimal view container element with a CSS id attribute suitable for test assertions.

- [ ] 5.1.3.1 Create `lib/observatory_web/components/fleet_command_components.ex` with `defmodule ObservatoryWeb.Components.FleetCommandComponents do use Phoenix.Component; def fleet_command_view(assigns), do: ~H"<div id=\"fleet-command-view\">Fleet Command</div>" end` — repeat for `session_cluster_components.ex` (`session-cluster-view`), `registry_components.ex` (`registry-view`), `scheduler_components.ex` (`scheduler-view`), `forensic_components.ex` (`forensic-view`), and `god_mode_components.ex` (`god-mode-view`) at their canonical paths under `lib/observatory_web/components/` `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.1.3.2 In `lib/observatory_web/live/dashboard_live.html.heex`, add a dispatch block that calls the appropriate component function for each `view_mode` atom, e.g. for `:fleet_command` call `<ObservatoryWeb.Components.FleetCommandComponents.fleet_command_view {assigns} />` — or use aliased imports at the top of `dashboard_live.ex` to call `FleetCommandComponents.fleet_command_view(assigns)` inside a `case @view_mode do` block; ensure all six branches are covered `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.1.3.3 Write tests in `test/observatory_web/live/dashboard_live_test.exs` that mount DashboardLive with each of the six `view_mode` atoms (set via `assign/3` before render) and assert the rendered HTML contains the expected container id element (`fleet-command-view`, `session-cluster-view`, `registry-view`, `scheduler-view`, `forensic-view`, `god-mode-view`) for each, and that no `UndefinedFunctionError` or `FunctionClauseError` is raised `done_when: "mix test test/observatory_web/live/dashboard_live_test.exs"`

---

## 5.2 Fleet Command View

- [ ] **Section 5.2 Complete**

This section builds out the full `FleetCommandComponents` module beyond the stub created in Section 5.1, implementing the six-panel layout required by FR-12.5 and FR-12.6: the Mesh Topology Map canvas as the dominant element, plus throughput, cost heatmap, infrastructure health, latency, and mTLS status secondary panels. All panels must subscribe to the `swarm:update` PubSub topic and render graceful loading states when no data is present. The agent grid from the previous `:command` view is included as a collapsible sub-panel.

### 5.2.1 FleetCommandComponents Panel Layout

- [ ] **Task 5.2.1 Complete**
- **Governed by:** ADR-022
- **Parent UCs:** UC-0305

Implement the full `FleetCommandComponents.fleet_command_view/1` function component with a two-zone layout: a dominant canvas zone holding the Mesh Topology Map canvas element, and a secondary zone containing five named panel containers. All six layout elements must be present in the rendered HTML regardless of whether PubSub data has arrived. Each secondary panel must use a nil-safe accessor (e.g., `assigns[:mesh_data] || %{}`) so that nil assigns never raise `ArgumentError` or `KeyError`.

- [ ] 5.2.1.1 Replace the stub in `lib/observatory_web/components/fleet_command_components.ex` with a full `fleet_command_view/1` function component that renders: a `<div id="mesh-topology-canvas">` container (placeholder for the Canvas component from Phase 3), a `<div id="throughput-panel">` showing `assigns[:throughput_rate] || "Loading..."`, a `<div id="cost-heatmap-panel">` showing per-agent cost data from `assigns[:cost_heatmap] || []`, a `<div id="infrastructure-health-panel">` showing `assigns[:node_status] || "Loading..."`, a `<div id="latency-panel">` showing p50/p95/p99 from `assigns[:latency_metrics] || %{}`, and a `<div id="mtls-status-panel">` showing `assigns[:mtls_status] || "Loading..."` `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.2.1.2 Add `|> assign(:throughput_rate, nil) |> assign(:cost_heatmap, []) |> assign(:node_status, nil) |> assign(:latency_metrics, %{}) |> assign(:mtls_status, nil)` to the `mount/3` chain in `lib/observatory_web/live/dashboard_live.ex`; add a `handle_info({:swarm_update, payload}, socket)` clause in `lib/observatory_web/live/dashboard_swarm_handlers.ex` that destructures `payload` into the relevant assigns `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.2.1.3 Add a collapsible agent grid sub-panel to `fleet_command_view/1`: a toggle button with `phx-click="toggle_agent_grid"` and a conditional `<div id="agent-grid-panel">` that renders existing `CommandComponents` sub-components when `assigns[:agent_grid_open]` is true; add `|> assign(:agent_grid_open, false)` to `mount/3`; add `handle_event("toggle_agent_grid", _, socket)` in `dashboard_ui_handlers.ex` that toggles `agent_grid_open` `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.2.1.4 Write tests in `test/observatory_web/live/fleet_command_test.exs` asserting: (a) mounting with `view_mode: :fleet_command` and swarm mesh assigns populated renders all six container elements (`mesh-topology-canvas`, `throughput-panel`, `cost-heatmap-panel`, `infrastructure-health-panel`, `latency-panel`, `mtls-status-panel`); (b) mounting with all mesh assigns nil does not raise and all panel containers are present with placeholder content; (c) sending `toggle_agent_grid` event toggles `agent_grid_open` and the agent-grid-panel appears/disappears in rendered HTML `done_when: "mix test test/observatory_web/live/fleet_command_test.exs"`

### 5.2.2 PubSub Integration and Cost Heatmap Data Pipeline

- [ ] **Task 5.2.2 Complete**
- **Governed by:** ADR-022
- **Parent UCs:** UC-0305

Wire the `swarm:update` PubSub subscription to populate Fleet Command panel assigns in real time, and implement the cost heatmap data derivation from `state_delta.cumulative_session_cost` values in the DecisionLog stream. The heatmap must represent per-agent cost as a sorted list of `%{agent_id: string, cost: float}` maps stored in the `:cost_heatmap` assign.

- [ ] 5.2.2.1 In `lib/observatory_web/live/dashboard_swarm_handlers.ex`, ensure `handle_info({:swarm_update, payload}, socket)` extracts `payload.throughput_rate`, `payload.node_status`, `payload.latency_metrics`, `payload.mtls_status`, and `payload.agent_costs` (a list of `%{agent_id, cost}` maps derived from accumulated DecisionLog `state_delta.cumulative_session_cost` values) and assigns them to the socket; if any key is absent from payload, retain the existing socket assign value `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.2.2.2 In `lib/observatory_web/live/dashboard_live.ex` `mount/3`, confirm `Phoenix.PubSub.subscribe(Observatory.PubSub, "swarm:update")` is present; add `|> assign(:cost_heatmap, [])` to the assign chain; write a private helper `build_cost_heatmap(events)` in `lib/observatory_web/live/dashboard_data_helpers.ex` that accepts a list of `%DecisionLog{}` structs, groups by `identity.agent_id`, sums `state_delta.cumulative_session_cost`, and returns a sorted list `done_when: "mix compile --warnings-as-errors"`

---

## 5.3 Session Cluster and Registry Views

- [ ] **Section 5.3 Complete**

This section implements the full `SessionClusterComponents` and `RegistryComponents` modules covering FR-12.7 and FR-12.8. The Session Cluster view provides an active session list with entropy filtering, a Causal DAG drill-down that opens on session selection, a Live Scratchpad streaming `cognition.intent` values, a HITL Console, and collapsible sub-panels for Feed, Messages, Tasks, and Protocols. The Registry view provides a sortable Capability Directory and a Routing Logic Manager form with changeset-validated weight submissions.

### 5.3.1 SessionClusterComponents: Active Session List and Entropy Filter

- [ ] **Task 5.3.1 Complete**
- **Governed by:** ADR-022
- **Parent UCs:** UC-0306

Implement the session list and entropy filter toggle in `SessionClusterComponents`. The session list derives from socket assigns populated via `swarm:update` and `events:stream` PubSub. When `entropy_filter_active: true`, the rendered list shows only sessions whose accumulated `cognition.entropy_score` exceeds the configured threshold (default `0.7`). When the filtered list is empty, render an empty-state message. Session row clicks emit a `select_session` event setting `selected_session_id`.

- [ ] 5.3.1.1 Replace the stub in `lib/observatory_web/components/session_cluster_components.ex` with a `session_cluster_view/1` function component that renders: a filter toggle button with `phx-click="toggle_entropy_filter"`, a session list that iterates `assigns[:sessions] || []` filtered by `entropy_filter_active`, and a `<div id="session-cluster-view">` wrapper; each session row must have `phx-click="select_session"` with `phx-value-session_id` set to the session ID; when the filtered list is empty, render `<p class="empty-state">No high-entropy sessions.</p>` `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.3.1.2 Add `|> assign(:sessions, []) |> assign(:entropy_filter_active, false) |> assign(:entropy_threshold, 0.7) |> assign(:selected_session_id, nil)` to `mount/3`; add `handle_event("toggle_entropy_filter", _, socket)` in `dashboard_navigation_handlers.ex` toggling `entropy_filter_active`; add `handle_event("select_session", %{"session_id" => id}, socket)` setting `selected_session_id: id` `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.3.1.3 Write tests in `test/observatory_web/live/session_cluster_test.exs` asserting: (a) sending `select_session` with `session_id: "sess-xyz-789"` sets `selected_session_id` to `"sess-xyz-789"` and rendered HTML contains `causal-dag-panel`, `live-scratchpad-panel`, and `hitl-console-panel` elements; (b) activating entropy filter with all sessions below threshold renders the empty-state message and no exception is raised `done_when: "mix test test/observatory_web/live/session_cluster_test.exs"`

### 5.3.2 SessionClusterComponents: Causal DAG Drill-Down, Live Scratchpad, HITL Console, and Sub-Panels

- [ ] **Task 5.3.2 Complete**
- **Governed by:** ADR-022
- **Parent UCs:** UC-0306

Implement the drill-down panel that appears when `selected_session_id` is non-nil, rendering the Causal DAG, Live Scratchpad, and HITL Console as panel containers. Collapsible sub-panels for Feed, Messages, Tasks, and Protocols must be present and toggled by `phx-click` events. When no DecisionLog events exist for the selected session, each drill-down sub-panel renders an empty state without raising.

- [ ] 5.3.2.1 In `session_cluster_view/1`, add a conditional drill-down section rendered when `assigns[:selected_session_id]` is non-nil: `<div id="causal-dag-panel">` (delegates to Phase 3 DAG component or stub), `<div id="live-scratchpad-panel">` streaming `cognition.intent` values from `assigns[:scratchpad_intents] || []`, and `<div id="hitl-console-panel">` (delegates to Phase 4 HITL component or stub); add collapsible sub-panel toggles for Feed, Messages, Tasks, and Protocols using `phx-click="toggle_subpanel"` with a `phx-value-panel` attribute `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.3.2.2 Add `|> assign(:scratchpad_intents, []) |> assign(:feed_panel_open, false) |> assign(:messages_panel_open, false) |> assign(:tasks_panel_open, false) |> assign(:protocols_panel_open, false)` to `mount/3`; add `handle_event("toggle_subpanel", %{"panel" => panel}, socket)` in `dashboard_ui_handlers.ex` that toggles the relevant `_{panel}_panel_open` assign; populate `scratchpad_intents` from DecisionLog `cognition.intent` values filtered by `selected_session_id` in `handle_info/2` `done_when: "mix compile --warnings-as-errors"`

### 5.3.3 RegistryComponents: Capability Directory and Routing Logic Manager

- [ ] **Task 5.3.3 Complete**
- **Governed by:** ADR-022
- **Parent UCs:** UC-0307

Implement `RegistryComponents.registry_view/1` with a two-panel layout: a sortable Capability Directory table and a Routing Logic Manager form. The Capability Directory must be sortable by `:agent_type`, `:instance_count`, and `:capability_version` via column header click events. The Routing Logic Manager form submits weight changes via `phx-submit="update_route_weight"` and renders inline validation errors from the changeset on invalid submissions.

- [ ] 5.3.3.1 Replace the stub in `lib/observatory_web/components/registry_components.ex` with `registry_view/1` rendering: a `<div id="registry-view">` wrapper, a sortable table with column headers that emit `phx-click="sort_capability_directory"` with `phx-value-field` set to `"agent_type"`, `"instance_count"`, or `"capability_version"`, and rows from `Enum.sort_by(assigns[:agent_types] || [], &Map.get(&1, assigns[:capability_sort_field] || :agent_type))`; a Routing Logic Manager section with a `phx-submit="update_route_weight"` form per route entry, with an editable weight `<input>` field and an inline error span `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.3.3.2 Add `|> assign(:agent_types, []) |> assign(:route_weights, %{}) |> assign(:capability_sort_field, :agent_type) |> assign(:capability_sort_dir, :asc) |> assign(:route_weight_errors, %{})` to `mount/3`; add `handle_event("sort_capability_directory", %{"field" => field}, socket)` toggling sort direction if field unchanged, else setting new field ascending; add `handle_event("update_route_weight", %{"agent_type" => type, "weight" => w}, socket)` that parses weight as integer, validates `>= 0`, and either updates `route_weights` assign or sets an error in `route_weight_errors` `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.3.3.3 Write tests in `test/observatory_web/live/dashboard_live_test.exs` asserting: (a) `update_route_weight` with `weight: "70"` updates the routing configuration and rendered form shows no validation error; (b) `update_route_weight` with `weight: "-1"` leaves the routing configuration unchanged and renders an inline validation error; (c) `sort_capability_directory` with `field: "instance_count"` sets `capability_sort_field` to `:instance_count` and rendered directory rows are ordered by instance count descending `done_when: "mix test test/observatory_web/live/dashboard_live_test.exs"`

---

## 5.4 Scheduler and Forensic Inspector Views

- [ ] **Section 5.4 Complete**

This section implements `SchedulerComponents` and `ForensicComponents` covering FR-12.9 and FR-12.10. The Scheduler view renders the Cron Job Dashboard with distinct visual job state indicators, the Dead Letter Queue panel with per-entry retry actions, and the Heartbeat Monitor zombie agent list. The Forensic Inspector view renders a full-text queryable Message Archive, a Cost Attribution panel with grouping controls, a Security webhook log panel, a Policy Engine rule manager, and collapsible sub-panels for Errors, Analytics, and Timeline.

### 5.4.1 SchedulerComponents: Cron Job Dashboard, DLQ Panel, and Heartbeat Monitor

- [ ] **Task 5.4.1 Complete**
- **Governed by:** ADR-022
- **Parent UCs:** UC-0308

Implement `SchedulerComponents.scheduler_view/1` with three panel containers. The Cron Job Dashboard must apply `cron-status-pending`, `cron-status-running`, and `cron-status-failed` CSS classes to job rows based on the job's state field. The DLQ panel must render a `Retry` button per entry via `phx-click="retry_dlq_entry"` with `phx-value-entry_id`; when the DLQ list is empty, render an empty state message. The Heartbeat Monitor must render a zombie agent list from `assigns[:zombie_agents] || []`.

- [ ] 5.4.1.1 Replace the stub in `lib/observatory_web/components/scheduler_components.ex` with `scheduler_view/1` rendering: `<div id="scheduler-view">` wrapper; a Cron Job Dashboard section iterating `assigns[:cron_jobs] || []` with each row carrying `class={"cron-status-#{job.state}"}` (where `job.state` is `"pending"`, `"running"`, or `"failed"`) and displaying `job.name`, `job.next_run_at`, `job.last_success_at`, and `job.consecutive_failures`; a DLQ section that either renders `<p class="empty-state">No failed deliveries.</p>` when `(assigns[:dlq_entries] || []) == []` or renders each entry with a payload preview, failure reason, and `<button phx-click="retry_dlq_entry" phx-value-entry_id={entry.id}>Retry</button>`; a Heartbeat Monitor section listing zombie agents `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.4.1.2 Add `|> assign(:cron_jobs, []) |> assign(:dlq_entries, []) |> assign(:zombie_agents, [])` to `mount/3`; add `handle_event("retry_dlq_entry", %{"entry_id" => id}, socket)` in `dashboard_swarm_handlers.ex` that calls the backend re-enqueue function, updates the matching DLQ entry state to `"pending"` in socket assigns on success, or sets a flash error on failure `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.4.1.3 Write tests in `test/observatory_web/live/dashboard_live_test.exs` asserting: (a) `retry_dlq_entry` with a valid entry ID transitions that entry's state to `"pending"` and the rendered entry shows a pending indicator; (b) mounting with an empty DLQ list renders the empty-state message without raising; (c) mounting with cron jobs of states `"pending"`, `"running"`, and `"failed"` produces rows with CSS classes `cron-status-pending`, `cron-status-running`, and `cron-status-failed` in distinct elements `done_when: "mix test test/observatory_web/live/dashboard_live_test.exs"`

### 5.4.2 ForensicComponents: Message Archive, Cost Attribution, Security, and Policy Engine

- [ ] **Task 5.4.2 Complete**
- **Governed by:** ADR-022
- **Parent UCs:** UC-0309

Implement `ForensicComponents.forensic_view/1` with four named panel containers plus collapsible sub-panels. The Message Archive must render a `phx-submit="search_archive"` form and list `assigns[:archive_results] || []`; when results are empty, render `"No events found."`. The Cost Attribution panel must render breakdowns from `assigns[:cost_attribution] || []` grouped by `assigns[:cost_group_by] || :agent_id` with a grouping selector. The Security panel renders `assigns[:webhook_log] || []` with per-entry signature validation status. The Policy Engine renders `assigns[:policy_rules] || []` with add/edit/remove controls.

- [ ] 5.4.2.1 Replace the stub in `lib/observatory_web/components/forensic_components.ex` with `forensic_view/1` rendering: `<div id="forensic-view">` wrapper; `<div id="message-archive-panel">` with a search form (`phx-submit="search_archive"`, text input named `query`) and a results list or empty state text `"No events found."`; `<div id="cost-attribution-panel">` with a `phx-change="set_cost_group_by"` selector (`<select name="group_by">` with options `agent_id` and `session_id`) and a cost breakdown table; `<div id="security-panel">` listing webhook log entries with signature status badges; `<div id="policy-engine-panel">` listing rules with a `phx-submit="add_policy_rule"` form; collapsible sub-panels for Errors, Analytics, and Timeline `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.4.2.2 Add `|> assign(:archive_results, []) |> assign(:cost_attribution, []) |> assign(:cost_group_by, :agent_id) |> assign(:webhook_log, []) |> assign(:policy_rules, []) |> assign(:error_list_open, false) |> assign(:analytics_panel_open, false) |> assign(:timeline_panel_open, false)` to `mount/3`; add `handle_event("search_archive", %{"query" => q}, socket)` searching DecisionLog data and storing results; add `handle_event("set_cost_group_by", %{"group_by" => g}, socket)` updating `cost_group_by`; add `handle_event("add_policy_rule", params, socket)` appending to `policy_rules` `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.4.2.3 Write tests in `test/observatory_web/live/dashboard_live_test.exs` asserting: (a) `search_archive` with a valid agent ID renders matching event rows; (b) `search_archive` with a query matching no events renders `"No events found."` without raising and the `cost-attribution-panel` remains present; (c) `set_cost_group_by` with `"session_id"` sets `cost_group_by` to `:session_id` and rendered Cost Attribution shows session-grouped breakdowns `done_when: "mix test test/observatory_web/live/dashboard_live_test.exs"`

---

## 5.5 God Mode View and Global Instructions

- [ ] **Section 5.5 Complete**

This section implements the full `GodModeComponents` module covering FR-12.11, FR-12.12, and FR-12.13. God Mode introduces a double-confirmation kill-switch tracked by the `kill_switch_confirm_step` socket assign cycling through `nil | :first | :second`, danger-zone CSS classes enforced structurally in the rendered HTML (`god-mode-panel`, `god-mode-button-danger`, `god-mode-border`), and a Global Instructions panel with per-agent-class editors, single-step inline confirmation, and PubSub dispatch on confirmed push.

### 5.5.1 GodModeComponents: Kill-Switch Double-Confirm State Machine

- [ ] **Task 5.5.1 Complete**
- **Governed by:** ADR-022
- **Parent UCs:** UC-0310, UC-0311

Implement the kill-switch state machine in `DashboardLive` with three event handlers (`kill_switch_click`, `kill_switch_first_confirm`, `kill_switch_second_confirm`) and one cancel handler (`kill_switch_cancel`). The `kill_switch_second_confirm` handler must guard that `kill_switch_confirm_step == :second` before dispatching the pause command; if the step is not `:second`, it must reset to `nil` without dispatching. A single `kill_switch_click` event must not dispatch the pause command. Dismissal at either step must reset `kill_switch_confirm_step` to `nil` without any partial execution.

- [ ] 5.5.1.1 In `lib/observatory_web/live/dashboard_session_control_handlers.ex`, add: `handle_event("kill_switch_click", _, socket)` setting `kill_switch_confirm_step: :first`; `handle_event("kill_switch_first_confirm", _, socket)` setting `kill_switch_confirm_step: :second` (does NOT dispatch pause); `handle_event("kill_switch_second_confirm", _, %{assigns: %{kill_switch_confirm_step: :second}} = socket)` calling `dispatch_mesh_pause(socket)` then resetting `kill_switch_confirm_step: nil`; `handle_event("kill_switch_second_confirm", _, socket)` catch-all resetting to `nil` without dispatch; `handle_event("kill_switch_cancel", _, socket)` resetting to `nil`; add `|> assign(:kill_switch_confirm_step, nil)` to `mount/3` `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.5.1.2 In `lib/observatory_web/components/god_mode_components.ex`, replace the stub with `god_mode_view/1` that renders: `<div id="god-mode-view">` wrapper; a kill-switch section with class `god-mode-panel` containing a button with class `god-mode-button-danger` and `phx-click="kill_switch_click"`; a first confirmation modal rendered when `assigns[:kill_switch_confirm_step] == :first` with a `Confirm` button (`phx-click="kill_switch_first_confirm"`) and a `Cancel` button (`phx-click="kill_switch_cancel"`); a second confirmation rendered when `kill_switch_confirm_step == :second` with the same pattern `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.5.1.3 Write tests in `test/observatory_web/live/god_mode_test.exs` asserting: (a) sending `kill_switch_click`, `kill_switch_first_confirm`, `kill_switch_second_confirm` in sequence transitions `kill_switch_confirm_step` through `nil -> :first -> :second -> nil` and the mesh pause command is dispatched; (b) sending `kill_switch_click` followed by `kill_switch_cancel` resets `kill_switch_confirm_step` to `nil` and no pause is dispatched; (c) sending only `kill_switch_click` (no subsequent events) leaves `kill_switch_confirm_step` at `:first` and no pause is dispatched; (d) sending `kill_switch_second_confirm` when `kill_switch_confirm_step` is `nil` does not dispatch the pause command and resets to `nil` `done_when: "mix test test/observatory_web/live/god_mode_test.exs"`

### 5.5.2 God Mode Danger Zone CSS Classes

- [ ] **Task 5.5.2 Complete**
- **Governed by:** ADR-022
- **Parent UCs:** UC-0312

Enforce the danger-zone styling contract by defining the three required CSS classes in the application stylesheet and verifying that `GodModeComponents` uses only these classes (not inline styles or standard `primary-button` variants) on all action containers, destructive buttons, and the Global Instructions editor border. The CSS class definitions must appear in the application stylesheet under a `/* God Mode danger zone */` comment block.

- [ ] 5.5.2.1 In `assets/css/app.css` (or the appropriate stylesheet consumed by the build pipeline), add under `/* God Mode danger zone */`: `.god-mode-panel { border: 2px solid #ef4444; border-radius: 0.375rem; padding: 1rem; }`, `.god-mode-button-danger { background-color: #ef4444; color: #ffffff; font-weight: 600; padding: 0.5rem 1rem; border-radius: 0.25rem; cursor: pointer; }`, `.god-mode-border { border: 2px solid #f59e0b; border-radius: 0.375rem; padding: 0.5rem; }` — using Tailwind `@apply` directives if Tailwind is in use `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.5.2.2 Audit `lib/observatory_web/components/god_mode_components.ex` to confirm: no button element within `god_mode_view/1` uses the class `primary-button` or `btn-primary`; no action container or button uses an inline `style` attribute; the kill-switch button carries `class="god-mode-button-danger"`; the "Push to all" button for instructions carries `class="god-mode-button-danger"`; all primary action container divs carry `class="god-mode-panel"`; the Global Instructions editor container carries `class="god-mode-border"` `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.5.2.3 Write tests in `test/observatory_web/live/god_mode_test.exs` asserting: (a) mounting with `view_mode: :god_mode` renders HTML containing at least one element with class `god-mode-button-danger` and at least one with class `god-mode-panel`; (b) no button element in the rendered God Mode HTML has the class `primary-button`; (c) the Global Instructions editor container has class `god-mode-border` `done_when: "mix test test/observatory_web/live/god_mode_test.exs"`

### 5.5.3 God Mode Global Instructions Panel and PubSub Push

- [ ] **Task 5.5.3 Complete**
- **Governed by:** ADR-022
- **Parent UCs:** UC-0313

Implement the Global Instructions panel in `GodModeComponents.god_mode_view/1` with per-agent-class editors pre-populated from socket assigns on mount. Each editor has a "Push to all" button that initiates a single inline confirmation via the `instructions_confirm_pending` assign. Confirmed pushes dispatch the instruction text via PubSub to all running instances of the agent class. The push is not auto-saved; navigating away without confirming silently discards the edit. Success and failure banners are rendered based on the backend response.

- [ ] 5.5.3.1 In `god_mode_view/1`, add a Global Instructions section rendering each entry in `assigns[:agent_classes] || []`: a `<textarea class="god-mode-border">` pre-populated with `agent_class.current_prompt`, a `<button class="god-mode-button-danger" phx-click="push_instructions_intent" phx-value-agent_class={agent_class.name}>Push to all</button>`, and a conditional inline confirmation section rendered when `assigns[:instructions_confirm_pending] == agent_class.name` containing `Confirm` (`phx-click="push_instructions_confirm" phx-value-agent_class={agent_class.name}`) and `Cancel` (`phx-click="push_instructions_cancel" phx-value-agent_class={agent_class.name}`) buttons; render success/failure banners from `assigns[:instructions_banner] || %{}` per agent class `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.5.3.2 Add `|> assign(:agent_classes, []) |> assign(:instructions_confirm_pending, nil) |> assign(:instructions_banner, %{})` to `mount/3`; populate `agent_classes` by calling a backend function on mount; add `handle_event("push_instructions_intent", %{"agent_class" => cls}, socket)` setting `instructions_confirm_pending: cls`; add `handle_event("push_instructions_confirm", %{"agent_class" => cls}, socket)` that broadcasts the instruction text via `Phoenix.PubSub.broadcast/3` to the agent class topic, sets a success or failure banner, and resets `instructions_confirm_pending: nil`; add `handle_event("push_instructions_cancel", %{"agent_class" => cls}, socket)` resetting `instructions_confirm_pending: nil` `done_when: "mix compile --warnings-as-errors"`
- [ ] 5.5.3.3 Write tests in `test/observatory_web/live/god_mode_test.exs` asserting: (a) sending `push_instructions_intent` and `push_instructions_confirm` in sequence for agent class `"orchestrator"` calls PubSub broadcast and renders a success banner; (b) sending `push_instructions_intent` followed by a `keydown "1"` navigation event dispatches no instruction update and no banner renders; (c) simulating a backend error on `push_instructions_confirm` renders a failure banner and `instructions_confirm_pending` resets to `nil` while the editor text is preserved `done_when: "mix test test/observatory_web/live/god_mode_test.exs"`

---
