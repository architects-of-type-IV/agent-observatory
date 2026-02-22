---
id: FRD-012
title: Hypervisor UI Architecture Functional Requirements
date: 2026-02-22
status: draft
source_adr: [ADR-022]
related_rule: []
---

# FRD-012: Hypervisor UI Architecture

## Purpose

The Hypervisor UI Architecture replaces the existing seven-tab navigation structure with six purpose-built views, each answering a distinct operational question about the agent mesh. The new views are expressed as six `view_mode` atoms and are rendered by six dedicated component modules. Every panel from the previous navigation (Feed, Protocols, Analytics, Timeline, Messages, Tasks, Command, Pipeline, Agents) is absorbed as a sub-panel inside one of the six new views; no existing component module is deleted.

The architecture is implemented in the Observatory Phoenix LiveView application. Navigation is entirely keyboard-driven (keys `1`–`6` for primary view selection, `Esc` for drill-down dismissal) with localStorage persistence. Legacy `view_mode` atoms stored in localStorage from previous sessions are recovered gracefully by defaulting to `:fleet_command` rather than crashing the LiveView mount.

## Functional Requirements

### FR-12.1: Six view_mode Atoms and Default View

The LiveView MUST recognize exactly six valid `view_mode` atoms: `:fleet_command`, `:session_cluster`, `:registry`, `:scheduler`, `:forensic`, and `:god_mode`. On every mount the LiveView MUST assign `view_mode: :fleet_command` as the initial socket assign before reading localStorage. After the client pushes the persisted `view_mode` value, the socket assign MUST be updated only if the pushed value is one of the six valid atoms. `:fleet_command` MUST be the default view shown to first-time users and to users whose localStorage value cannot be resolved.

**Positive path**: A first-time user loads the page; the mount assigns `view_mode: :fleet_command`; the Fleet Command view renders immediately without a blank frame.

**Negative path**: A user loads the page with no localStorage key set; the client push event does not fire; the LiveView remains on `:fleet_command` and does not crash.

---

### FR-12.2: Keyboard Shortcuts 1–6 for View Selection

The LiveView MUST bind keyboard keys `"1"` through `"6"` to view selection via a `phx-window-keydown` or equivalent client-side hook. Key `"1"` MUST navigate to `:fleet_command`, key `"2"` to `:session_cluster`, key `"3"` to `:registry`, key `"4"` to `:scheduler`, key `"5"` to `:forensic`, and key `"6"` to `:god_mode`. On each key press the LiveView MUST update the `view_mode` socket assign, persist the new atom to localStorage, and re-render the active view component. No other keys in the `"1"`–`"6"` range MAY be mapped to a different view.

**Positive path**: A user presses `"3"` from any view; the socket assign transitions to `view_mode: :registry`; the Registry view renders; localStorage is updated to `"registry"`.

**Negative path**: A user presses `"7"`; no `view_mode` change occurs; the current view remains active; no error is logged.

---

### FR-12.3: Esc Key Dismisses Drill-Down and Returns to Fleet Command

The LiveView MUST handle the `"Escape"` key event. When a drill-down panel is open (indicated by a non-nil socket assign such as `selected_session_id`, `inspected_agent_id`, or `drill_down_open: true`), pressing `Escape` MUST close the drill-down by clearing the relevant assign and MUST NOT change `view_mode`. When no drill-down is open and the current `view_mode` is not `:fleet_command`, pressing `Escape` MUST navigate to `:fleet_command` and persist that value to localStorage. When `view_mode` is already `:fleet_command` and no drill-down is open, the `Escape` key MUST be a no-op.

**Positive path**: A user is on `:session_cluster` with a causal DAG drill-down open; pressing `Escape` clears the DAG panel; `view_mode` remains `:session_cluster`; a second `Escape` press navigates to `:fleet_command`.

**Negative path**: A user is already on `:fleet_command` with no drill-down; pressing `Escape` triggers no socket update and no re-render.

---

### FR-12.4: localStorage Mismatch Recovery

The client-side hook responsible for restoring `view_mode` from localStorage MUST wrap the value lookup in a try/catch (JavaScript) or equivalent guard. When the stored value is not one of the six valid view name strings (`"fleet_command"`, `"session_cluster"`, `"registry"`, `"scheduler"`, `"forensic"`, `"god_mode"`), the hook MUST NOT push the invalid value to the LiveView. The LiveView `handle_event` for view navigation MUST additionally guard against unrecognized atoms using a rescue or a case clause with a catch-all that assigns `view_mode: :fleet_command`. Legacy atoms (`:command`, `:pipeline`, `:agents`, `:protocols`, `:feed`, `:errors`, `:analytics`, `:timeline`) MUST be treated as unrecognized and MUST resolve to `:fleet_command`.

**Positive path**: A user's localStorage contains `"command"` from a previous session; the client hook detects it is not in the valid set; it either clears the key or pushes `"fleet_command"`; the LiveView mounts on `:fleet_command`.

**Negative path**: The client hook pushes `"command"` anyway (e.g., a browser with an older hook version); the LiveView `handle_event` receives `:command`; the catch-all clause fires; `view_mode` is set to `:fleet_command`; no `FunctionClauseError` occurs; a warning-level log entry is emitted with the unrecognized atom.

---

### FR-12.5: Six Dedicated Component Modules

Each view MUST be rendered by exactly one dedicated component module. The modules MUST be named and located as follows: `ObservatoryWeb.Components.FleetCommandComponents` at `lib/observatory_web/components/fleet_command_components.ex`, `ObservatoryWeb.Components.SessionClusterComponents` at `lib/observatory_web/components/session_cluster_components.ex`, `ObservatoryWeb.Components.RegistryComponents` at `lib/observatory_web/components/registry_components.ex`, `ObservatoryWeb.Components.SchedulerComponents` at `lib/observatory_web/components/scheduler_components.ex`, `ObservatoryWeb.Components.ForensicComponents` at `lib/observatory_web/components/forensic_components.ex`, and `ObservatoryWeb.Components.GodModeComponents` at `lib/observatory_web/components/god_mode_components.ex`. Each module MUST expose at least one public function component (using `def` with `%Phoenix.LiveView.Socket{}` assigns or the `attr`/`slot` macro pattern) that accepts the full socket assigns map and renders the view's primary layout. No view MUST be rendered by a module whose name does not match its entry above.

**Positive path**: The LiveView `render/1` function pattern-matches on `view_mode: :registry` and delegates to `RegistryComponents.registry_view(assigns)`. The component renders without undefined function errors.

**Negative path**: A developer adds a `RegistryView` module in the wrong namespace; the LiveView continues to call `RegistryComponents`; the mismatch is caught at compile time if the module is used in the render clause, surfacing an `UndefinedFunctionError`.

---

### FR-12.6: Fleet Command View Panels

The `:fleet_command` view, rendered by `FleetCommandComponents`, MUST include the following panels in its primary layout: (1) a Mesh Topology Map canvas component (as specified in FRD-008) occupying the dominant area of the viewport, (2) a throughput panel displaying aggregate message volume per second across the mesh, (3) a cost heatmap panel displaying per-agent cumulative session cost derived from `state_delta.cumulative_session_cost` in the DecisionLog stream, (4) an infrastructure health panel summarizing node status, (5) a latency panel displaying p50/p95/p99 latency metrics, and (6) an mTLS status indicator panel showing certificate validity and mutual-auth posture. The agent grid previously rendered by the `:command` view MUST be available as a sub-panel or collapsible section within this view rather than a separate view.

**Positive path**: A user navigates to `:fleet_command`; the Mesh Topology Map canvas renders at the center; all five secondary panels populate with live data from the `swarm:update` PubSub topic.

**Negative path**: The PubSub topic delivers no data within the mount cycle; each panel renders in a loading or empty state with placeholder text rather than raising a nil dereference.

---

### FR-12.7: Session Cluster View Panels

The `:session_cluster` view, rendered by `SessionClusterComponents`, MUST include the following panels: (1) an Active Session List displaying all currently open sessions with their agent count and status, (2) an Entropy Alert filter that limits the session list to sessions whose `cognition.entropy_score` exceeds the configured alert threshold (as specified in FRD-009), (3) a Causal DAG drill-down panel (from FRD-008) that opens when a session is selected and displays the full directed acyclic graph of DecisionLog steps for that session, (4) a Live Scratchpad panel that streams `cognition.intent` field values from the selected session's DecisionLog events in real time, (5) a HITL Console panel (from FRD-011) for human-in-the-loop message injection and interrupt signaling, and (6) the agent detail panel previously rendered by the `:agents` view, accessible in the sidebar of a selected session. The Feed, Messages, Tasks, and Protocols panels from the previous navigation MUST be available as collapsible sub-panels within this view.

**Positive path**: A user selects a high-entropy session from the filtered list; the Causal DAG drill-down opens and renders the session's step graph; the Live Scratchpad begins streaming `cognition.intent` updates; the HITL Console is available for injection.

**Negative path**: A user activates the Entropy Alert filter when no sessions exceed the threshold; the session list renders empty with a "no high-entropy sessions" message; no JavaScript error occurs.

---

### FR-12.8: Registry View Panels

The `:registry` view, rendered by `RegistryComponents`, MUST include the following panels: (1) a Capability Directory listing all registered agent types with their current instance counts and model version distribution (derived from `identity.agent_type` and `identity.capability_version` fields in the DecisionLog stream), and (2) a Routing Logic Manager panel exposing traffic weighting controls for each agent type and displaying the circuit breaker status per route. The Capability Directory MUST be sortable by agent type name, instance count, and model version. The Routing Logic Manager MUST display the current weight for each route as an editable numeric field; changes submitted from the UI MUST be sent to the backend via a `phx-submit` form event.

**Positive path**: A user opens `:registry`; the Capability Directory renders with three agent types, their counts, and version distributions; the user updates a traffic weight and submits; the LiveView receives the `phx-submit` event and updates the routing configuration.

**Negative path**: A user submits a traffic weight of `-1`; the backend changeset validation rejects the value; the form renders an inline error; the routing configuration is not modified.

---

### FR-12.9: Scheduler View Panels

The `:scheduler` view, rendered by `SchedulerComponents`, MUST include the following panels: (1) a Cron Job Dashboard displaying upcoming scheduled tasks with their next execution time, last success time, and consecutive failure count, (2) a Dead Letter Queue (DLQ) panel displaying failed webhook deliveries as specified in FRD-010, showing payload preview, failure reason, and a retry action per entry, and (3) a Heartbeat Monitor panel displaying the zombie agent list (agents that have missed their heartbeat window, as specified in FRD-010) and auto-scaling trigger events. The Cron Job Dashboard MUST distinguish between pending, running, and failed job states using distinct visual indicators. The DLQ retry action MUST trigger a `phx-click` event that re-enqueues the delivery without requiring a page reload.

**Positive path**: A user opens `:scheduler`; three upcoming cron jobs are listed; the DLQ panel shows two failed deliveries with retry buttons; a user clicks retry; the delivery is re-enqueued and the DLQ entry moves to a pending state.

**Negative path**: The DLQ is empty; the panel renders an empty state message; no error is raised; the Heartbeat Monitor continues to render independently.

---

### FR-12.10: Forensic Inspector View Panels

The `:forensic` view, rendered by `ForensicComponents`, MUST include the following panels: (1) a Message Archive panel providing full-text queryable history of all DecisionLog events, searchable by `identity.agent_id`, `meta.trace_id`, and free-text across `cognition.intent` and `action.tool_call`, (2) a Cost Attribution panel showing cumulative cost breakdowns grouped by Agent ID or Session ID derived from `state_delta.cumulative_session_cost`, (3) a Security panel displaying the webhook delivery log with per-entry signature validation status (valid/invalid/missing), and (4) a Policy Engine panel showing the current set of Deny/Allow rules governing inter-agent communication with controls to add, edit, or remove rules. The error list, analytics dashboard, and timeline views from the previous navigation MUST be available as collapsible sub-panels within this view rather than top-level views.

**Positive path**: A user searches the Message Archive for agent ID `"agent-abc"`; the panel renders all matching DecisionLog events; the user switches to Cost Attribution and groups by Session ID; a cost breakdown table renders.

**Negative path**: The Message Archive search returns no results; the panel renders an empty state; the query does not time out or raise; cost attribution continues to render independently.

---

### FR-12.11: God Mode Kill-Switch Double-Confirm Requirement

The `:god_mode` view, rendered by `GodModeComponents`, MUST include a Global Kill-Switch control that pauses all non-essential routing across the mesh. Activating the kill-switch MUST require two separate, sequential user confirmations before the pause command is dispatched. The first confirmation MUST be a modal dialog presenting the scope and consequences of the action; the second confirmation MUST be a second distinct modal or inline confirmation step that cannot be reached without completing the first. A single button press MUST NOT dispatch the pause command. Dismissing either confirmation dialog at any step MUST cancel the action entirely without any partial execution. The LiveView MUST track confirmation state in socket assigns (e.g., `kill_switch_confirm_step: nil | :first | :second`) and MUST reset the step to `nil` on any dismissal or cancellation.

**Positive path**: A user clicks the kill-switch button; the first confirmation modal renders; the user confirms; the second confirmation renders; the user confirms again; the pause command is dispatched and the mesh enters paused state; `kill_switch_confirm_step` resets to `nil`.

**Negative path**: A user clicks the kill-switch button and dismisses the first modal; `kill_switch_confirm_step` resets to `nil`; no pause command is dispatched; the mesh state is unchanged.

---

### FR-12.12: God Mode Danger Zone Styling

All interactive controls in the `:god_mode` view MUST be visually distinguished from controls in other views using a danger zone aesthetic. The God Mode component layout MUST apply red border styling to all primary action containers using a CSS class defined in the application stylesheet (not inline styles). Button elements for destructive actions (kill-switch, push to all) MUST use a red-background variant distinct from the standard primary button style. The Global Instructions editor MUST be bordered in amber or red to signal elevated-risk context. The `GodModeComponents` module MUST NOT reuse the same button component variants used for safe actions in other views; it MUST use dedicated danger-variant component calls or explicitly named CSS classes such as `god-mode-panel`, `god-mode-button-danger`, and `god-mode-border`.

**Positive path**: A user navigates to `:god_mode`; the panel renders with red borders on action containers and red-background buttons; the visual distinction is immediately apparent without relying solely on text labels.

**Negative path**: A developer accidentally uses the standard `primary_button` component for the kill-switch; a code review check (or style lint) catches that the `god-mode-button-danger` class is absent; the build or review process flags the deviation.

---

### FR-12.13: God Mode Global Instructions Push Mechanism

The `:god_mode` view MUST include a Global Instructions panel containing a plain-text or rich-text editor for each registered agent class. The editor MUST be pre-populated with the current system prompt for that agent class on view mount. A "Push to all" button MUST be present per agent class. Clicking "Push to all" MUST send the edited instruction text to a LiveView event handler that dispatches the update to all running instances of that agent class via PubSub. The push MUST be preceded by a single inline confirmation step (not a full double-confirm as with the kill-switch). The LiveView MUST display a success or failure banner after the push completes, derived from the backend response. The instructions panel MUST NOT auto-save; changes MUST only propagate on explicit "Push to all" activation.

**Positive path**: A user edits the system prompt for agent class `"orchestrator"` and clicks "Push to all"; a confirmation step renders; the user confirms; the LiveView dispatches the update; a success banner renders; all running orchestrator agents receive the new instruction via PubSub.

**Negative path**: The user edits the prompt and navigates away without clicking "Push to all"; the edit is discarded; no instruction update is dispatched; no data loss warning is required because the panel does not auto-save.

---

## Out of Scope (Phase 1)

- Role-based access control restricting God Mode to specific operator accounts
- Per-view layout persistence beyond `view_mode` atom (e.g., panel sizing, column ordering)
- Mobile-responsive breakpoints for the Mesh Topology Map canvas
- Multi-monitor or detachable panel windowing
- Animated view transitions between `view_mode` states
- Server-side rendering of the Mesh Topology Map canvas (client-side Canvas API only)
- Undo/redo for God Mode instruction edits

## Related ADRs

- [ADR-022](../../decisions/ADR-022-six-view-ui-architecture.md) -- Defines the six Hypervisor views, their keyboard shortcuts, component module names, and migration from the existing seven-tab navigation
- [ADR-014](../../decisions/ADR-014-decision-log-envelope.md) -- DecisionLog field contracts consumed by Fleet Command and Forensic Inspector panels
- [ADR-018](../../decisions/ADR-018-entropy-score-loop-detection.md) -- Entropy score thresholds consumed by the Session Cluster entropy filter
