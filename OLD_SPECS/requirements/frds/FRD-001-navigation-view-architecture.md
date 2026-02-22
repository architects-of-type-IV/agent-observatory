---
id: FRD-001
title: Navigation and View Architecture Functional Requirements
date: 2026-02-21
status: draft
source_adr: [ADR-001, ADR-003, ADR-008]
related_rule: []
---

# FRD-001: Navigation and View Architecture

## Purpose

The Observatory dashboard is a Phoenix LiveView single-page application that exposes a multi-view operational interface for swarm monitoring. Navigation is managed through a `view_mode` assign on `ObservatoryWeb.DashboardLive`, which controls which view section is rendered in the main content area. The navigation structure was redesigned in ADR-001 and ADR-003 to prioritize operational situational awareness over raw data exploration, culminating in the `:command` default established by ADR-008.

This FRD governs the allowed view mode atoms, their keyboard shortcut mappings, the tab hierarchy (primary vs. standard vs. overflow), the unified control plane layout for `:command`, and the localStorage persistence and recovery behavior for view state.

## Functional Requirements

### FR-1.1: Canonical View Mode Atoms

The `view_mode` socket assign in `ObservatoryWeb.DashboardLive` MUST accept only the following atoms: `:overview`, `:command`, `:pipeline`, `:agents`, `:protocols`, `:feed`, `:tasks`, `:messages`, `:errors`, `:analytics`, `:timeline`, `:teams`, `:agent_focus`. Any string value arriving via the `"set_view"` event or the `"restore_state"` event MUST be converted to an atom using `String.to_existing_atom/1`. If the conversion raises `ArgumentError` (i.e., the atom was never defined), the socket MUST fall through to the current default without crashing.

**Positive path**: A client sends `phx-value-mode="command"`. `DashboardFilterHandlers.handle_set_view/2` calls `String.to_existing_atom("command")`, returns `:command`, and assigns it to `:view_mode`. The Command view is rendered.

**Negative path**: A client sends `phx-value-mode="unknown_mode"` or a localStorage value from a future build contains an obsolete atom. The `rescue ArgumentError` block in `DashboardUIHandlers.maybe_restore/3` catches the error and leaves `:view_mode` unchanged, keeping the operator on the current view rather than crashing the LiveView process.

---

### FR-1.2: Default View Mode on Mount

`ObservatoryWeb.DashboardLive.mount/3` MUST assign `:view_mode` to `:overview` as the initial in-process value. The `StatePersistence` JS hook attached to `id="view-mode-toggle"` MUST immediately push a `"restore_state"` event with the value stored under the localStorage key `"observatory:view_mode"`. If that value is `"command"` (or any valid atom string), the `handle_event("restore_state", ...)` handler MUST overwrite the initial `:overview` with the restored atom, resulting in `:command` being the effective view for returning operators.

**Positive path**: A returning operator loads the page. `mount/3` sets `:overview` briefly. The `StatePersistence` hook fires synchronously on mount, pushing `restore_state` with `%{"view_mode" => "command"}`. The LiveView updates `:view_mode` to `:command` before the first meaningful render for that client.

**Negative path**: A new operator loads the page for the first time. localStorage has no `"observatory:view_mode"` key. The `StatePersistence` hook pushes `restore_state` with a nil or empty string value for `view_mode`. `DashboardUIHandlers.maybe_restore/3` pattern-matches on `nil` or `""` and returns the socket unchanged, leaving `:view_mode` as `:overview`.

---

### FR-1.3: View Mode Persistence via localStorage

When the `view_mode` changes via any path (keyboard shortcut, tab click, or cross-view navigation), the LiveView MUST push a `"view_mode_changed"` JS event with the new mode string. The `StatePersistence` hook MUST write the value to `localStorage["observatory:view_mode"]` upon receiving this event, ensuring the selection survives page reloads.

**Positive path**: The operator presses `2` (keyboard shortcut for `:command`). The `KeyboardShortcuts` hook pushes `set_view` with `mode: "command"`. `handle_set_view/2` assigns `:command` and calls `push_event("view_mode_changed", %{view_mode: "command"})`. The `StatePersistence` hook's `handleEvent("view_mode_changed", ...)` listener writes `"command"` to localStorage. On next page load, the state is restored.

**Negative path**: The view is changed programmatically by `DashboardNavigationHandlers` (e.g., `jump_to_feed`) without calling `handle_set_view/2`. These handlers assign `:view_mode` directly via `Phoenix.Component.assign/3` without pushing `"view_mode_changed"`. As a result, the localStorage value is NOT updated, and the next page load restores the previously persisted mode rather than the jump destination. This is acceptable; jump navigations are transient cross-view links.

---

### FR-1.4: Keyboard Shortcut Mapping

The `KeyboardShortcuts` JS hook (attached to `id="dashboard-root"`) MUST map numeric keys `1` through `9` to view modes in the following order, with `0` mapping to index 9 (i.e., `:errors`):

| Key | Index | View Mode   |
|-----|-------|-------------|
| `1` | 0     | `:overview` |
| `2` | 1     | `:command`  |
| `3` | 2     | `:pipeline` |
| `4` | 3     | `:agents`   |
| `5` | 4     | `:protocols`|
| `6` | 5     | `:feed`     |
| `7` | 6     | `:tasks`    |
| `8` | 7     | `:messages` |
| `9` | 8     | `:errors`   |
| `0` | 9     | `:errors`   |

The hook MUST NOT fire when the focused element is an `INPUT` or `TEXTAREA`. It MUST NOT fire when `e.metaKey` or `e.ctrlKey` is held. The `?` key MUST push `"toggle_shortcuts_help"`. The `Escape` key MUST push `"keyboard_escape"`. The `f` key MUST focus the nearest `input[name="q"]` element without pushing a server event.

**Positive path**: The operator presses `6` with focus on the document body. The hook computes index `5`, maps to `"feed"`, and pushes `set_view` with `mode: "feed"`. The server assigns `:feed` and the feed view renders.

**Negative path**: The operator presses `6` while focused inside a text input (e.g., the search box). The hook returns early after the `tagName === "INPUT"` check. No `set_view` event is pushed. The view mode is unchanged.

---

### FR-1.5: Tab Hierarchy and Nav Rendering

The navigation bar (`id="view-mode-toggle"`) MUST render all defined view mode tabs as buttons with `phx-click="set_view"` and `phx-value-mode` set to the atom string. The active tab MUST receive CSS classes `bg-zinc-700 text-zinc-200 shadow-sm`; inactive tabs MUST receive `text-zinc-500 hover:text-zinc-300`. The `:errors` tab MUST display a red badge with the count of errors when `@errors` is non-empty. The `:overview` tab MUST display the pipeline progress counter `(completed/total)` when `@swarm_state.pipeline.total > 0`.

**Positive path**: The operator is on `:command` with 3 errors. The `:command` tab renders with the active class. The `:errors` tab renders with a red badge showing `3`. All other tabs render with inactive classes.

**Negative path**: All `@errors` is an empty list. The red badge on the `:errors` tab is not rendered (`:if={mode == :errors && @errors != []}` evaluates false). The `:errors` tab label renders without any annotation.

---

### FR-1.6: Unified Control Plane for :command View Mode

The `:command` view mode MUST render a single stacked layout that combines agent grid, fleet status bar, pipeline progress, recent alerts, recent errors, and recent messages into one scrollable surface via `ObservatoryWeb.Components.CommandComponents`. No tab-switching between separate Command, Pipeline, and Agents views MUST be required to answer the question "do I need to intervene?" The `:command` view MUST NOT replace or hide the Feed, Errors, or Protocols views; those remain navigable via their own tab buttons and keyboard shortcuts.

**Positive path**: The operator presses `2`. The `:command` view renders `command_view.html.heex`, which assembles fleet status bar, cluster cards (project -> swarm -> agent hierarchy), recent errors section, recent messages section, and alerts panel in a single scrollable column. A right-side detail panel appears when `@selected_command_agent` or `@selected_command_task` is non-nil.

**Negative path**: A developer adds a new "Pipeline" sub-section that requires clicking a separate tab or navigating away from `:command` to view pipeline progress. This violates FR-1.6. Pipeline progress MUST be surfaced within the `:command` view itself (via the fleet status bar's task progress mini-bar and the swarm pipeline progress bar).

---

### FR-1.7: Collapsible Sidebar State

`ObservatoryWeb.DashboardLive` MUST maintain a `:sidebar_collapsed` boolean assign (default `false`). The `"toggle_sidebar"` event handler MUST toggle this boolean and push a `"filters_changed"` client event with `%{sidebar_collapsed: to_string(new_val)}` so the `StatePersistence` hook can persist the sidebar state independently of view mode.

**Positive path**: The operator clicks the sidebar collapse control. `handle_event("toggle_sidebar", ...)` sets `:sidebar_collapsed` to `true` and pushes `"filters_changed"`. The sidebar CSS collapses. On next load, `restore_state` restores `sidebar_collapsed: "true"`, and `maybe_restore/3` assigns `true` to `:sidebar_collapsed`.

**Negative path**: A restore event arrives with `sidebar_collapsed: "false"` or any value other than `"true"`. The `maybe_restore(socket, :sidebar_collapsed, _)` catch-all clause leaves `:sidebar_collapsed` unchanged (effectively `false`). The sidebar renders expanded.

---

### FR-1.8: Cross-View Navigation Jumps

`ObservatoryWeb.DashboardNavigationHandlers` MUST handle programmatic navigation events (`"jump_to_feed"`, `"jump_to_timeline"`, `"jump_to_agents"`, `"jump_to_tasks"`) that both change the view mode and apply a session filter simultaneously. These handlers MUST clear `:selected_event` and `:selected_task` assigns on every jump. The cross-view jump MUST NOT call `handle_set_view/2` and therefore MUST NOT push `"view_mode_changed"` to the client (see FR-1.3).

**Positive path**: The operator clicks "view in feed" on an agent row. The `"jump_to_feed"` event fires with `session_id`. `DashboardNavigationHandlers.handle_event/3` assigns `:feed` to `:view_mode` and the session ID to `:filter_session_id`, and clears selections. The feed renders filtered to that agent's events.

**Negative path**: A navigation jump arrives without a `"session_id"` key in params. The function head `handle_jump_to_feed(%{"session_id" => sid}, socket)` does not match; Phoenix raises a `FunctionClauseError`. This is acceptable -- callers MUST always supply `session_id` for jump events.

---

### FR-1.9: Component Module Responsibilities

The `:command` view MUST be rendered exclusively by `ObservatoryWeb.Components.CommandComponents` (defined in `lib/observatory_web/components/command_components.ex`), which MUST use `embed_templates "command_components/*"` to load its HEEX templates from the `command_components/` subdirectory. Agent data for the command view MUST be derived inside the component via the private `collect_agents/3` function (which takes `teams`, `events`, and `now`) rather than being pre-computed in `prepare_assigns/1`. This keeps the heavyweight agent derivation scoped to the `:command` render path.

**Positive path**: The LiveView renders `:command`. It passes `@teams`, `@events`, and `@now` as assigns to `CommandComponents.command_view/1`. The component calls `collect_agents/3` internally, builds the cluster hierarchy, and renders without any additional assigns prepared by `DashboardLive`.

**Negative path**: A developer moves `collect_agents/3` into `prepare_assigns/1` so it runs on every tick regardless of view mode. This introduces unnecessary CPU overhead when the operator is on `:feed` or `:errors`. The agent derivation MUST remain inside `CommandComponents` and MUST NOT be called from `prepare_assigns/1`.

---

## Out of Scope (Phase 1)

- Per-view keyboard shortcut overlays (beyond the `?` help modal)
- Drag-and-drop tab reordering
- User-configurable tab visibility (hiding unwanted tabs)
- Deep-link URLs that encode view mode and filters as query parameters

## Related ADRs

- [ADR-001](../../decisions/ADR-001-swarm-control-center-nav.md) -- Establishes the 7-tab hierarchy and the collapse of Teams into Agents
- [ADR-003](../../decisions/ADR-003-unified-control-plane.md) -- Merges Command, Pipeline, and Agents into a single `:command` view with collapsible sidebar
- [ADR-008](../../decisions/ADR-008-default-view-evolution.md) -- Documents the `:feed` -> `:overview` -> `:command` default view evolution and the localStorage rescue behavior
