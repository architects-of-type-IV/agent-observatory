---
id: FRD-002
title: Agent Block Feed System Functional Requirements
date: 2026-02-21
status: draft
source_adr: [ADR-002]
related_rule: []
---

# FRD-002: Agent Block Feed System

## Purpose

The Observatory feed view presents a live event stream grouped by agent session rather than as a flat chronological list. Each session is rendered as a collapsible block with a metadata header and a sub-feed of tool executions and standalone events. Subagents spawned by a parent session are nested as child blocks within the parent's block. Consecutive tool calls within any block are grouped into collapsible `{:tool_chain, pairs}` tuples for scannable rendering.

This architecture is governed by ADR-002. The primary modules involved are `ObservatoryWeb.DashboardFeedHelpers` (grouping and pairing logic), `ObservatoryWeb.Components.FeedComponents` (delegation router), and the `ObservatoryWeb.Components.Feed.*` namespace (session group, tool chain, standalone event, and feed view components).

## Functional Requirements

### FR-2.1: Session-Based Feed Grouping

`ObservatoryWeb.DashboardFeedHelpers.build_feed_groups/2` MUST group all events by their `session_id` field, producing one session group map per distinct `session_id`. The resulting list MUST be sorted in descending order of each group's `start_time` (the `inserted_at` of the `:SessionStart` event, or the earliest event timestamp if no `:SessionStart` exists). `build_feed_groups/2` MUST accept an optional `teams` list as its second argument to enable agent name cross-referencing; callers MAY pass an empty list when team data is unavailable.

**Positive path**: Five sessions are in the event store. `build_feed_groups(events, teams)` returns a list of five session group maps sorted newest-first. Each map has a `:session_id`, `:agent_name` (resolved from the teams list or cwd basename), `:role`, `:segments`, `:start_time`, `:end_time`, and `:is_active` key.

**Negative path**: All events share a single `session_id`. `build_feed_groups/2` returns a list with exactly one session group containing all events. The operator sees one block rather than N individual event rows.

---

### FR-2.2: Session Group Metadata

Each session group map produced by `build_session_group/3` MUST include the following fields:

| Field | Type | Source |
|-------|------|--------|
| `session_id` | string | event `session_id` |
| `agent_name` | string or nil | `build_agent_name_map/2` result |
| `role` | `:lead` or `:standalone` | presence of `:SubagentStart` events |
| `segments` | list of segment maps | `build_segments/1` |
| `session_start` | event or nil | first `:SessionStart` event |
| `session_end` | event or nil | first `:SessionEnd` event |
| `stop_event` | event or nil | last `:Stop` event |
| `model` | string or nil | extracted from `:SessionStart` payload |
| `cwd` | string or nil | most recent non-nil `cwd` field |
| `permission_mode` | string or nil | most recent non-nil `permission_mode` field |
| `source_app` | string or nil | first event's `source_app` |
| `event_count` | integer | total event count for session |
| `tool_count` | integer | count of `:PreToolUse` events |
| `subagent_count` | integer | count of `:subagent` type segments |
| `total_duration_ms` | integer or nil | diff between `:SessionStart` and `:SessionEnd` |
| `is_active` | boolean | `session_end == nil` |

**Positive path**: A session has a `:SessionStart` event with `payload["model"] = "claude-sonnet-4-6"` and a `:SessionEnd` event. The resulting group has `model: "claude-sonnet-4-6"`, `is_active: false`, and `total_duration_ms` set to the millisecond difference between start and end.

**Negative path**: A session has events but no `:SessionStart` event (e.g., events were received mid-session). `session_start` is `nil`, `model` falls back to the first non-nil `model_name` field across all events, `start_time` is the earliest `inserted_at` across all events, and `total_duration_ms` is `nil`.

---

### FR-2.3: Role Detection

The `:role` field of a session group MUST be set to `:lead` when the session's sorted events contain at least one event with `hook_event_type == :SubagentStart`. Otherwise, `:role` MUST be `:standalone`. The `:worker` and `:relay` role atoms defined in `ObservatoryWeb.Components.Feed.SessionGroup` role badge rendering MUST be rendered when role data arrives from team member enrichment; the `build_session_group/3` function itself MUST NOT produce these atoms -- they originate from team membership data merged into the group by the caller.

**Positive path**: A session has a `:SubagentStart` event. `build_session_group/3` sets `role: :lead`. The `SessionGroup` component renders the `LEAD` badge.

**Negative path**: A session with no `:SubagentStart` events but whose team member record has `role: :worker` (from the teams list). `build_session_group/3` sets `role: :standalone`. If the caller does not merge team member role data into the group map, the component renders the `SESSION` badge. Callers that do merge team data MAY overwrite `:role` with `:worker` or `:relay` post-construction.

---

### FR-2.4: Segment Architecture

`build_segments/1` MUST split a session's sorted events into one or more segment maps. Each segment MUST have a `:type` key with value `:parent` or `:subagent`. A `:parent` segment contains events that occur outside all subagent spans. A `:subagent` segment is bracketed by a `SubagentStart` / `SubagentStop` event pair matched by `agent_id` from the event payload. When no `:SubagentStart` events exist, `build_segments/1` MUST return a single `:parent` segment containing all events. Subagent segments MUST include: `:agent_id`, `:agent_type`, `:start_event`, `:stop_event`, `:start_time`, `:end_time`, `:events`, `:tool_pairs`, `:event_count`, and `:tool_count`.

**Positive path**: A parent session spawns two sequential subagents. `build_segments/1` returns three segment maps: `%{type: :parent, ...}` for events before the first subagent, `%{type: :subagent, agent_id: "abc", ...}`, and `%{type: :subagent, agent_id: "def", ...}`, followed by a final `%{type: :parent, ...}` for events after the last subagent stop.

**Negative path**: A `:SubagentStart` event has no matching `:SubagentStop` (the subagent is still running). `extract_subagent_spans/1` produces a span with `stop_event: nil` and `end_time: nil`. `collect_span_events/2` collects all events from the start time to the end of the session (because `span.end_time == nil` disables the upper-bound filter). The segment renders as an in-progress subagent block.

---

### FR-2.5: SubagentStart/SubagentStop Event Handling

`SubagentStart` and `SubagentStop` events MUST fire on the PARENT session's `session_id`. Subagents DO NOT receive their own `session_id` UUIDs in the event stream. The `agent_id` used to match start-stop pairs MUST be read from `event.payload["agent_id"]`. Unmatched `:SubagentStart` events (where no stop event shares the same `agent_id`) MUST be treated as in-progress subagent spans rather than as errors. Unmatched `:SubagentStop` events (no corresponding start) MUST be silently ignored and MUST NOT appear in the rendered output.

**Positive path**: A `:SubagentStart` event arrives with `payload["agent_id"] = "ac67b7c"`. A later `:SubagentStop` event arrives with the same agent_id. `extract_subagent_spans/1` pairs them. The subagent block renders with both a start indicator and a stop indicator.

**Negative path**: A `:SubagentStop` event arrives with `agent_id = "xyz"` but no prior `:SubagentStart` with the same ID exists. `Enum.find(stops, fn s -> s.agent_id == start.agent_id end)` never returns a match for this stop. The stop event is not referenced from any span. The `segment_by_spans/2` reducer encounters the `:SubagentStop` event in the main loop, hits the `event.hook_event_type == :SubagentStop` clause, and discards it from the parent accumulator. It does not appear in any segment.

---

### FR-2.6: Parallel Subagent Overlap Handling

When multiple subagents are active simultaneously (their time ranges overlap), events that fall within multiple spans MUST appear in ALL applicable subagent blocks. `in_any_span?/2` MUST return `true` for an event if its `inserted_at` falls within ANY active span's `[start_time, end_time)` range, excluding the `:SubagentStart` and `:SubagentStop` boundary events themselves. Events in overlapping spans MUST NOT appear in the `:parent` segment.

**Positive path**: Subagent A runs from T=10 to T=30. Subagent B runs from T=20 to T=40. An event at T=25 falls within both spans. `collect_span_events/2` includes it in both subagent A's events list and subagent B's events list. The operator sees the event in both blocks.

**Negative path**: An event at T=5, before either subagent starts. `in_any_span?/2` returns `false`. The event accumulates in the parent segment. It renders in the `:parent` segment before the first subagent block.

---

### FR-2.7: Tool Pair Construction

`pair_tool_events/1` MUST pair `:PreToolUse` events with their corresponding `:PostToolUse` or `:PostToolUseFailure` events using the `tool_use_id` field as the join key. Each pair map MUST include: `:pre` (the pre-event), `:post` (the post-event or `nil`), `:duration_ms` (from the post-event's `duration_ms` field, or `nil` if no post-event), `:status` (`:in_progress`, `:success`, or `:failure`), `:tool_use_id`, and `:tool_name` (from the pre-event). A `:PreToolUse` with no matching post MUST produce a pair with `post: nil` and `status: :in_progress`.

**Positive path**: A session has a `:PreToolUse` event with `tool_use_id = "tid-1"` and `tool_name = "Read"`, followed by a `:PostToolUse` event with `tool_use_id = "tid-1"` and `duration_ms = 42`. The pair map has `status: :success`, `duration_ms: 42`, `tool_name: "Read"`.

**Negative path**: A `:PreToolUse` event with `tool_use_id = nil`. `pair_tool_events/1` filters out events where `tool_use_id` is falsy (the guard `e.tool_use_id` evaluates false for nil). This pre-event does not produce a pair and does not appear in the tool chain. It MAY appear as a standalone event instead if it is not filtered by `@feed_hidden_types`.

---

### FR-2.8: Standalone Event Filtering

`get_standalone_events/2` MUST exclude from the standalone events list any event whose `tool_use_id` is present in the set of paired tool use IDs, AND any event whose `hook_event_type` is in the hidden types list `[:SessionStart, :SessionEnd, :Stop, :SubagentStart, :SubagentStop, :PreCompact]`. Events not matching either exclusion MUST appear as standalone events in the segment timeline.

**Positive path**: A session has a `:UserMessage` event (not in the hidden types list, no `tool_use_id`). It appears as a `{:event, user_message_event}` entry in the segment timeline returned by `build_segment_timeline/2`.

**Negative path**: A `:SessionStart` event is in the event list. Even though it has no `tool_use_id`, it matches the `@feed_hidden_types` exclusion. It does not appear as a standalone event. The session start is instead surfaced through the session group header via the `:session_start` field of the group map.

---

### FR-2.9: Segment Timeline Construction

`build_segment_timeline/2` MUST produce a chronologically sorted list of timeline items by merging tool pair items and standalone event items, then grouping consecutive tool pair items into `{:tool_chain, [pair1, pair2, ...]}` tuples. Each non-tool item MUST appear as a `{:event, event}` tuple. A single tool pair MUST still be wrapped in a `{:tool_chain, [pair]}` tuple (single-element list). A standalone event that occurs between two tool pairs MUST break the chain, producing two separate `{:tool_chain, ...}` tuples with the `{:event, ...}` tuple between them.

**Positive path**: Segment events produce three tool pairs (T=1, T=3, T=5) and one standalone event (T=4). `build_segment_timeline/2` returns: `[{:tool_chain, [pair@1, pair@3]}, {:event, event@4}, {:tool_chain, [pair@5]}]`.

**Negative path**: Segment events produce five consecutive tool pairs with no interleaved standalone events. `build_segment_timeline/2` returns: `[{:tool_chain, [p1, p2, p3, p4, p5]}]` -- a single chain of five pairs. The `ToolChain` component renders this with a collapsible header summarizing all five tools.

---

### FR-2.10: Tool Chain Summary Helpers

`chain_tool_summary/1` MUST return a human-readable string summarizing the tools in a chain, grouping by tool name with frequency counts. Tool names occurring more than once MUST be suffixed with ` x{count}`. Single-occurrence tools MUST appear without a count. Tools MUST be sorted by frequency descending. `chain_total_duration/1` MUST sum `duration_ms` across all pairs in the chain, returning `nil` if all pairs have `nil` duration. `chain_status/1` MUST return `:in_progress` if any pair has `status: :in_progress`, `:has_failures` if any pair has `status: :failure` (and none are in progress), `:success` if all pairs are successful, or `:mixed` otherwise.

**Positive path**: A chain with three `Read` pairs and one `Edit` pair. `chain_tool_summary/1` returns `"Read x3, Edit"`. `chain_total_duration/1` returns the sum of all four `duration_ms` values. `chain_status/1` returns `:success` if all four are successful.

**Negative path**: A chain with one in-progress pair (no post-event) and two successful pairs. `chain_status/1` returns `:in_progress` because `Enum.any?(pairs, &(&1.status == :in_progress))` is true. The chain header renders with an in-progress indicator regardless of the completed pairs.

---

### FR-2.11: Agent Name Resolution

`build_agent_name_map/2` MUST build a map from `session_id` to display name using two sources, with team data taking precedence over cwd-derived names. Team names MUST be indexed by both `:session_id` and `:agent_id` fields of each team member map. CWD-derived names MUST use `Path.basename/1` of the `:SessionStart` event's `cwd` field. The merge MUST apply `Map.merge(session_start_names, team_names)` so that team-provided names overwrite cwd-derived names for the same session.

**Positive path**: A session's `:SessionStart` event has `cwd = "/Users/xander/code/project"`. The team's member list includes an entry with `session_id` equal to that session's ID and `name: "lead"`. The resolved name is `"lead"` (team name overwrites `"project"` from cwd).

**Negative path**: A session has no `:SessionStart` event and does not appear in any team's member list. `build_agent_name_map/2` has no entry for that `session_id`. The `session_group` component calls `agent_display_name/1`, which falls back to `short_session(group.session_id)` -- the first 8 characters of the session UUID.

---

### FR-2.12: Recursive ToolChain Component

`ObservatoryWeb.Components.Feed.ToolChain` (defined in `lib/observatory_web/components/feed/tool_chain.ex`) MUST render collapsible tool chain blocks with a summary header. When a chain contains only one pair, the component MUST render the single tool inline without a group header (no collapsible wrapper). When a chain contains multiple pairs, the component MUST render a collapsible header using `chain_tool_summary/1` output, with child pairs rendered as individual tool execution blocks. The component uses `embed_templates "tool_chain/*"` and imports `ObservatoryWeb.DashboardFeedHelpers` for the summary and duration helpers.

**Positive path**: A `{:tool_chain, [pair1, pair2, pair3]}` tuple arrives. The `ToolChain` component renders a collapsible group header with summary text (e.g., `"Bash x2, Read"`) and duration. Expanding the header reveals three individual tool execution blocks.

**Negative path**: A `{:tool_chain, [single_pair]}` tuple arrives. The `ToolChain` component detects a single-element list and renders the tool execution block inline without a collapsible wrapper, avoiding unnecessary nesting for single-step operations.

---

### FR-2.13: FeedComponents Delegation

`ObservatoryWeb.Components.FeedComponents` (defined in `lib/observatory_web/components/feed_components.ex`) MUST act as a delegation router with no logic of its own. It MUST delegate `feed_view/1` to `ObservatoryWeb.Components.Feed.FeedView`, `session_group/1` to `ObservatoryWeb.Components.Feed.SessionGroup`, `tool_execution_block/1` to `ObservatoryWeb.Components.Feed.ToolExecutionBlock`, and `standalone_event/1` to `ObservatoryWeb.Components.Feed.StandaloneEvent`. Callers importing `FeedComponents` MUST be able to use all four component functions without directly referencing the child modules.

**Positive path**: A LiveView template imports `ObservatoryWeb.Components.FeedComponents` and calls `<.session_group group={group} .../>`. The call delegates to `SessionGroup.session_group/1` without any additional logic. The session block renders correctly.

**Negative path**: A developer adds business logic (conditional rendering, data transformation) to `FeedComponents` itself. This violates FR-2.13. All rendering logic MUST live in the child modules under `ObservatoryWeb.Components.Feed.*`. `FeedComponents` MUST remain a pure delegation module.

---

## Out of Scope (Phase 1)

- Per-agent feed filtering from within the feed view (filtering is applied via `DashboardFilterHandlers.handle_filter_agent/2` which switches view to `:feed` with a session filter)
- Persistent collapse state for individual session blocks across page reloads
- Virtual scrolling or pagination for feeds with more than 500 events
- Search within a single agent's sub-feed

## Related ADRs

- [ADR-002](../../decisions/ADR-002-agent-block-feed.md) -- Establishes the agent-block grouping model, segment architecture, and tool chain grouping approach
