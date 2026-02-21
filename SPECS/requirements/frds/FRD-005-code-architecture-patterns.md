---
id: FRD-005
title: Code Architecture Patterns Functional Requirements
date: 2026-02-21
status: draft
source_adr: [ADR-006, ADR-010, ADR-011, ADR-012]
related_rule: []
---

# FRD-005: Code Architecture Patterns

## Purpose

This document specifies the functional requirements for four cross-cutting code architecture patterns that govern how the Observatory codebase is structured. These patterns apply to all present and future code: the elimination of unused Ash domains in favour of plain modules (ADR-006), the component file split pattern using `embed_templates` (ADR-010), the handler delegation pattern for LiveView modules (ADR-011), and the dual data source architecture for team state (ADR-012).

Each pattern has measurable consequences: module size limits, specific file naming conventions, function signature contracts, and data access rules. These requirements are intended to prevent regressions and provide concrete acceptance criteria for code review.

## Functional Requirements

### FR-5.1: Ash Domain Scope Restriction

The codebase MUST contain only Ash domains for data that is persistent, queryable, and benefits from Ash framework features (CRUD actions, policy auth, API generation). The three active Ash domains are `Observatory.Events`, `Observatory.AgentTools`, and `Observatory.Costs`. New Ash domains MUST NOT be created for ephemeral coordination data such as agent messages, task pipeline state, or real-time annotations.

**Positive path**: A developer needs to store agent messages. They use `Observatory.Mailbox` (a GenServer with ETS) rather than creating a new Ash domain, consistent with the existing pattern. `mix compile --warnings-as-errors` passes clean.

**Negative path**: A new `Observatory.Messaging` Ash domain is introduced for message routing. It adds compilation overhead, import confusion, and dead code warnings without providing value over Mailbox. This MUST be rejected in code review. If such a module exists, it MUST be moved to `tmp/trash/` (soft delete) rather than removed with `rm`.

---

### FR-5.2: Plain Module Replacements for Ephemeral Data

For ephemeral, real-time coordination data, plain GenServers with ETS MUST be used instead of Ash resources. The canonical implementations are: `Observatory.Mailbox` (agent messages), `Observatory.SwarmMonitor` (task pipeline state from `tasks.jsonl`), and `Observatory.Notes` (ephemeral annotations). These modules MUST NOT be replaced with Ash resources.

**Positive path**: `Observatory.Mailbox` handles all message routing via ETS + PubSub. It provides fast reads, PubSub integration, and no persistence requirements. No Ash resource for messages exists in the active codebase.

**Negative path**: An agent or developer proposes replacing `Observatory.Notes` with an Ash `Note` resource backed by SQLite. This MUST be rejected because notes are ephemeral and the Ash resource would add unnecessary persistence overhead without benefit.

---

### FR-5.3: Dead Code Removal via Soft Delete

When an Ash domain or other module is identified as unused (not connected to any real data flow), it MUST be soft-deleted by moving it to `<project-root>/tmp/trash/` rather than deleted with `rm`. The move preserves audit history. After the move, `mix compile --warnings-as-errors` MUST pass with zero warnings.

**Positive path**: The `Observatory.TaskBoard` module is identified as dead code (tasks come from `tasks.jsonl` via TaskManager). It is moved to `tmp/trash/dead-code-audit/`. `mix compile --warnings-as-errors` produces zero warnings.

**Negative path**: Running `rm lib/observatory/task_board.ex` violates the project-wide `rm` prohibition. Soft delete to `tmp/trash/` is the only permitted removal mechanism.

---

### FR-5.4: Component Module Size Limit

Phoenix Component modules MUST NOT exceed 300 lines. When a component module approaches or exceeds this limit, it MUST be split using the `embed_templates` pattern: logic and helper functions remain in the `.ex` file, and HEEx templates are extracted to co-located `.heex` files. The `.ex` file uses `embed_templates` to generate function heads from the `.heex` filenames.

**Positive path**: `FeedComponents` begins at 480 lines. After splitting, the `.ex` file is 95 lines and 6 `.heex` template files handle the rendering. The module compiles cleanly and the 300-line limit is respected.

**Negative path**: A component module grows to 600 lines with no split. This violates the size limit and MUST be flagged during review. The remedy is to split using `embed_templates`, not to add comments or compress whitespace.

---

### FR-5.5: Component File Split: .ex Content Rules

In a split component module, the `.ex` file MUST contain: the `use Phoenix.Component` directive, imports, `defdelegate` facades for backward compatibility when extracting sub-modules, helper functions used across templates, and multi-head pattern-matched dispatch functions (e.g., `defp segment(%{segment: %{type: :parent}} = assigns), do: parent_segment(assigns)`). The `.ex` file MUST NOT contain large inline HEEx templates that can be moved to `.heex` files.

**Positive path**: `DashboardFeedComponents.ex` contains `use Phoenix.Component`, four `import` lines, three dispatch functions, and six helper functions. All rendering is in `.heex` files. The file is 95 lines.

**Negative path**: A developer adds a 120-line inline `~H` block to the `.ex` file for a new feed segment type. This MUST be extracted to a `.heex` file instead.

---

### FR-5.6: Component File Split: .heex Content Rules

`.heex` template files generated via `embed_templates` MUST contain only HEEx markup and preprocessing blocks (`<% %>`). Preprocessing assigns (e.g., computed local variables derived from `@assigns`) MAY be placed in `<% %>` blocks at the top of the template. Function definitions MUST NOT appear in `.heex` files.

**Positive path**: `parent_segment.heex` opens with `<% color = segment_color(@segment) %>` to compute a display variable, then uses `<%= color %>` in the markup below. No `def` or `defp` appears in the file.

**Negative path**: A developer writes `<% defp helper(x), do: x + 1 %>` inside a `.heex` file. This will fail at compile time. Function definitions belong in the `.ex` file.

---

### FR-5.7: attr Incompatibility with embed_templates

Components that use `attr` declarations (Phoenix Component typed attributes) MUST NOT use `embed_templates`. The `attr` macro is incompatible with `embed_templates` and produces a compile-time "could not define attributes" error. Components with `attr` declarations MUST use inline `~H` sigils. If such a component exceeds 30 lines, it SHOULD be broken into smaller components rather than using `embed_templates`.

**Positive path**: A small button component declares `attr :label, :string` and uses an inline `~H` sigil for its 12-line template. No `embed_templates` is used.

**Negative path**: A developer attempts to use `embed_templates` on a module that contains `attr :items, :list`. This produces a compile-time error. The fix is to remove `embed_templates` and use inline `~H`, or to remove the `attr` declarations and use raw `assigns` access.

---

### FR-5.8: embed_templates Stale Beam Cleanup

When converting from `embed_templates` back to inline `~H` templates (or vice versa), `mix clean` MUST be run before the next `mix compile`. Stale `.beam` files from a previous `embed_templates` compilation cause redefinition warnings. This is a build hygiene requirement, not a runtime requirement.

**Positive path**: A developer converts a component from `embed_templates` to inline `~H`. They run `mix clean && mix compile --warnings-as-errors`. Zero warnings are produced.

**Negative path**: Running only `mix compile` after the conversion produces "function already defined" redefinition warnings from stale `.beam` files. The `mix clean` step is mandatory to avoid false-positive warnings.

---

### FR-5.9: Format-on-Save Race Condition Mitigation

When editing files that have format-on-save hooks active in the editor, file writes MUST use `sed -i ''` via Bash rather than the Edit tool's standard replace mechanism. The Edit tool performs a read-then-write sequence; if a format hook modifies the file between the read and the write, the edit produces a race condition (stale content error). Using `sed -i ''` for targeted in-place substitution avoids this failure mode.

**Positive path**: A developer uses `sed -i '' 's/old_function/new_function/g' lib/observatory_web/components/feed_components.ex` to rename a function across the file. The format hook fires after the sed write, not in between read and write. No stale content error occurs.

**Negative path**: The Edit tool reads `feed_components.ex` and computes a diff. Before the write fires, the format hook modifies the file. The Edit tool's write contains stale content from before the hook. The result is a corrupted edit or an error. This MUST be avoided in files with active format-on-save hooks.

---

### FR-5.10: LiveView Module Size and Responsibility Limit

`ObservatoryWeb.DashboardLive` MUST remain under 300 lines and MUST be limited to lifecycle callbacks: `mount/3`, `handle_info/2` clauses, `handle_event/3` dispatch clauses, and the `prepare_assigns/1` function. Domain-specific logic MUST NOT be implemented inline in `dashboard_live.ex`; it MUST be delegated to imported handler modules.

**Positive path**: `dashboard_live.ex` is 519 lines in the current codebase. New handler modules MUST be introduced to reduce this below 300 lines. Specifically, all handler logic should be in dedicated handler modules; `dashboard_live.ex` only dispatches.

**Negative path**: A developer adds a 50-line block of message formatting logic directly inside `handle_event("send_agent_message", ...)` in `dashboard_live.ex`. This violates domain cohesion and the size limit. The logic MUST be moved to `DashboardMessagingHandlers`.

---

### FR-5.11: Handler Module Naming Convention

Handler modules MUST follow the naming pattern `ObservatoryWeb.Dashboard{Domain}Handlers` where `{Domain}` is a capitalized noun describing the concern. Current handler modules are: `DashboardMessagingHandlers`, `DashboardTaskHandlers`, `DashboardNavigationHandlers`, `DashboardUIHandlers`, `DashboardFilterHandlers`, `DashboardNotificationHandlers`, `DashboardNotesHandlers`, `DashboardTeamInspectorHandlers`, `DashboardSwarmHandlers`, and `DashboardSessionControlHandlers`. New handler modules MUST follow this naming scheme.

**Positive path**: A new batch of events for "Analytics" interactions is added. The developer creates `ObservatoryWeb.DashboardAnalyticsHandlers` and imports it into `dashboard_live.ex`.

**Negative path**: A developer places analytics handler functions directly in `dashboard_live.ex` or creates a module named `ObservatoryWeb.AnalyticsHelper`. Neither follows the established convention.

---

### FR-5.12: Handler Module Return Contract

Handler functions in all `Dashboard*Handlers` modules MUST return a `socket` (not `{:noreply, socket}`). The `{:noreply, ...}` wrapping MUST be applied in `dashboard_live.ex` at the call site, typically via the `prepare_assigns/1` wrapper pattern: `Module.handle_event(e, p, s) |> then(&{:noreply, prepare_assigns(&1)})`. Alternatively, the single-line delegation form `def handle_event("filter", p, s), do: {:noreply, handle_filter(p, s) |> prepare_assigns()}` is also acceptable.

**Positive path**: `DashboardFilterHandlers.handle_filter/2` returns `socket`. In `dashboard_live.ex`, `def handle_event("filter", p, s), do: {:noreply, handle_filter(p, s) |> prepare_assigns()}` wraps the return correctly.

**Negative path**: A handler function returns `{:noreply, socket}`. When `dashboard_live.ex` applies `prepare_assigns(&1)` to this tuple, it receives a tuple instead of a socket and crashes with a `KeyError`. Handler functions MUST return bare sockets.

---

### FR-5.13: prepare_assigns/1 Mandatory Wrapping

Every `handle_event/3` and `handle_info/2` clause in `dashboard_live.ex` that modifies socket state MUST call `prepare_assigns/1` on the resulting socket before returning. `prepare_assigns/1` is the single point where all derived assigns (teams, sessions, filtered events, feed groups, etc.) are recomputed from raw state. Bypassing it produces stale view data.

**Positive path**: `handle_event("set_view", %{"mode" => m}, s)` delegates to `handle_set_view(m, s)` which returns a socket with `:view_mode` updated. `prepare_assigns/1` is applied before `{:noreply, ...}`. All dependent assigns are recomputed correctly.

**Negative path**: `handle_event("toggle_sidebar", ...)` returns `{:noreply, assign(socket, :sidebar_collapsed, true)}` without calling `prepare_assigns/1`. The `:teams` assign is not updated and the sidebar renders with stale team data.

---

### FR-5.14: Navigation Handler Guard Clause Pattern

Navigation `handle_event/3` clauses that share a single handler module MUST use a guard clause matching on the event name string: `def handle_event(e, p, s) when e in ["jump_to_timeline", "jump_to_feed", ...]`. The guard clause MUST be placed after all specific `handle_event` clauses in `dashboard_live.ex` so that specific event handlers take precedence. The navigation handler MUST return a socket (not a tuple) so the `prepare_assigns/1` wrapper applies uniformly.

**Positive path**: `DashboardNavigationHandlers.handle_event/3` receives `"jump_to_timeline"`, updates `:view_mode` and `:selected_event`, and returns `socket`. `dashboard_live.ex` wraps: `|> then(&{:noreply, prepare_assigns(&1)})`.

**Negative path**: A new navigation event `"jump_to_errors"` is added to `dashboard_live.ex` as a standalone `def handle_event` clause before the guard clause. This is redundant. It MUST instead be added to the guard clause's `when e in [...]` list and handled inside `DashboardNavigationHandlers`.

---

### FR-5.15: Dual Data Source: Disk as Authoritative

Team state MUST be derived from two independent sources: (1) disk state from `~/.claude/teams/` polled by `Observatory.TeamWatcher` every 2 seconds, and (2) event-derived state from `PreToolUse` and `SubagentStart` events on `"events:stream"`. Disk state is the authoritative source of truth for team existence and membership. When a team exists in both sources, the disk representation MUST win and the event-derived representation MUST be discarded.

**Positive path**: `DashboardTeamHelpers.merge_team_sources/2` is called with event-derived teams and disk teams. A team named `"my-team"` appears in both. The disk version is included in the result list; the event-derived version is excluded.

**Negative path**: A developer modifies `merge_team_sources/2` to prefer event-derived teams over disk teams. This produces phantom teams and lost membership data when agents crash before emitting events. Disk must always win.

---

### FR-5.16: enrich_team_members/3 Runtime Data Merging

`ObservatoryWeb.DashboardTeamHelpers.enrich_team_members/3` MUST merge event-derived runtime data into each team member map. For each member, it MUST compute and add the following keys: `event_count` (integer), `latest_event` (most recent event struct or nil), `status` (`:active`, `:idle`, `:ended`, or `:unknown`), `health` (from `compute_agent_health/2`), `health_issues` (list), `failure_rate` (float), `model` (string or nil), `cwd` (string or nil), `permission_mode` (string or nil), `current_tool` (map `%{tool_name: string, elapsed: integer}` or nil), and `uptime` (integer seconds or nil). The enrichment MUST use `Map.merge/2` so that disk-originated fields are preserved.

**Positive path**: A disk member `%{name: "worker-a", agent_id: "abc123", agent_type: "general-purpose"}` is enriched. The function finds 42 events for session `"abc123"`, computes `status: :active`, `model: "claude-opus-4-6"`, `uptime: 3600`, and returns the merged map with all fields present.

**Negative path**: A disk member has `agent_id: nil` (no runtime session yet). `enrich_team_members/3` skips event filtering for this member (empty `member_events` list). All computed keys default to nil or 0. The member is still included in the result with `:status` set to `:unknown`.

---

### FR-5.17: Member Key Access Pattern

Code that accesses team member maps MUST use bracket syntax (`member[:agent_id]`, `member[:session_id]`) rather than dot syntax (`member.agent_id`). This is required because disk-sourced members use `:agent_id` as the key while event-sourced members may use `:session_id`, and both are plain maps (not structs). Dot syntax on a plain map with a missing key raises `KeyError`.

**Positive path**: `find_agent_by_id(teams, agent_id)` uses `Enum.find(&(&1[:agent_id] == agent_id))`. This safely returns `nil` for members without `:agent_id` rather than crashing.

**Negative path**: `member.session_id` in a context where the member was loaded from disk produces `KeyError: key :session_id not found`. The bracket form `member[:session_id]` returns `nil` safely.

---

### FR-5.18: Dead Team Detection

Teams derived from events MUST be classified as dead when all three conditions hold: (1) the team has no corresponding entry in the disk-sourced `disk_teams` map (i.e., `source == :events`), (2) all members have `:status` in `[:ended, :idle, :unknown, nil]`, and (3) the most recent member event is older than 300 seconds (`@dead_team_threshold_sec 300`). Dead teams MUST have `dead?: true` set in their map. `prepare_assigns/1` MUST exclude dead teams from the `:teams` assign via `Enum.reject(& &1[:dead?])`.

**Positive path**: An event-derived team was active 10 minutes ago and all members have `:status` of `:ended`. `detect_dead_teams/2` marks it `dead?: true`. The dashboard `:teams` assign excludes it. The inspector panel prunes it from `:inspected_teams`.

**Negative path**: A disk-sourced team (source: `:disk`) is never marked dead regardless of member activity, because disk presence is authoritative. Even if all disk team members show `:ended` status, `dead?: false` is always set for disk teams.

---

### FR-5.19: prepare_assigns/1 Executed on Every State Change

`prepare_assigns/1` in `ObservatoryWeb.DashboardLive` MUST be called from `mount/3` (at the end, after all initial assigns are set) and from every `handle_event/3` and `handle_info/2` clause that modifies socket state. It MUST NOT be called conditionally. The function MUST recompute all derived assigns on every invocation: sessions, teams, feed groups, filtered events, errors, analytics, and timeline data.

**Positive path**: A `:tick` event fires every 1 second. `handle_info(:tick, socket)` updates `:now` and immediately calls `prepare_assigns/1`. Member `:status` fields (which compare event timestamps against `:now`) are recomputed on every tick, keeping the UI current.

**Negative path**: `prepare_assigns/1` is called only on `:new_event` and skipped on `:tick`. Member statuses become stale: a member that stopped emitting events 35 seconds ago never transitions from `:active` to `:idle` because the stale `:now` value keeps the difference below the 30-second idle threshold.

---

## Out of Scope (Phase 1)

- Server-side component caching to avoid redundant `prepare_assigns/1` recomputation on every tick.
- Normalizing disk member and event member schemas into a single unified struct.
- Automated dead team cleanup (removing disk config files for dead teams).
- Multi-node team discovery across distributed BEAM nodes.

## Related ADRs

- [ADR-006](../../decisions/ADR-006-dead-ash-domains.md) -- Dead Ash Domains Replaced with Plain Modules; establishes Ash domain scope restriction and plain module pattern.
- [ADR-010](../../decisions/ADR-010-component-file-split.md) -- Component File Split Pattern; defines `embed_templates` usage, size limits, and `attr` incompatibility.
- [ADR-011](../../decisions/ADR-011-handler-delegation.md) -- Handler Delegation Pattern for LiveView; defines handler module naming, return contract, and `prepare_assigns` wrapping.
- [ADR-012](../../decisions/ADR-012-dual-data-sources.md) -- Dual Data Source Architecture; defines disk-authoritative merging, member key access rules, and dead team detection.
