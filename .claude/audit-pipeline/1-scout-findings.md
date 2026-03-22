# Stage 1: Scout Findings -- Elixir Idioms Audit

**Date**: 2026-03-22
**Scope**: `lib/ichor/signals/` (27 files)
**Target**: Non-idiomatic Elixir + shape twins

Found **40 findings + 5 cross-file twins = 45 items** across 3 scout passes.

## Bugs (fix immediately)

| # | File:Line | Finding |
|---|-----------|---------|
| 4 | agent_watchdog.ex:241 | `maybe_unpause` case only matches `{:ok, _}` -- `{:error, _}` raises CaseClauseError |
| 9 | buffer.ex:32 | `init/1` `:ets.new` no ArgumentError guard -- crashes on supervisor restart |
| 28 | normalizer.ex:109 | `get_field` uses `\|\|` -- returns wrong value for falsy-but-valid (0, false, "") |
| 29 | normalizer.ex:105 | `coerce_hook_type` catch-all returns `:Stop` (real type) instead of `:unknown` |
| 21 | event_stream.ex:330 | `lookup_tool_start` guards on strings but events have atom `hook_event_type` |

## Shape Twins (merge)

| # | File:Line | Twin | Fix |
|---|-----------|------|-----|
| 1 | agent_lifecycle.ex:66-81 | `handle_team_create`/`handle_team_delete` | One function, signal atom as param |
| 6 | agent_watchdog.ex:385-424 | `check_done_signal`/`check_blocked_signal` | One `check_pane_signal/5` |
| 12 | bus.ex:124-156 | `deliver_to_fleet`/`deliver_to_role` | `Enum.each` + `length` |
| 26 | message.ex:37-62 | `build/3` duplicates `build/4` | Delegate `build/3` -> `build/4` with `[]` |
| 30 | operations.ex:13-49 | `check_inbox`/`check_operator_inbox` | One action, optional session_id |
| 34 | pane_scanner.ex:72-91 | `match_done`/`match_blocked` | One `match_marker/2` |

## Anti-patterns

| # | File:Line | Finding |
|---|-----------|---------|
| 3 | agent_watchdog.ex:165 | `safe_emit` with `function_exported?` guard -- unnecessary |
| 5 | agent_watchdog.ex:352+ | `agent[:session_id] \|\| agent[:id]` duplicated 3x |
| 7 | agent_watchdog.ex:436 | `Enum.reject \|> Map.new` should be `Map.filter` |
| 10 | buffer.ex:42 | Raw `Phoenix.PubSub.broadcast` bypasses Topics |
| 11 | bus.ex:55 | `DateTime.utc_now()` as ETS key -- microsecond collision |
| 13 | bus.ex:158 | "Delivered message" as 3 anonymous maps -- no struct |
| 15 | bus.ex:38 | Missing `:from` silently becomes `"system"` |
| 16 | catalog.ex:695 | `lookup!/1` never raises -- silently derives, violates `!` convention |
| 17 | entropy_tracker.ex:136 | catch-all `handle_info` missing `@impl true` |
| 19 | escalation_engine.ex:82 | `:agent_id` vs `:id` key mismatch with watchdog |
| 20 | event_payload.ex:1 | File `event_payload.ex` defines `TraceEvent` -- name mismatch |
| 22 | event_stream.ex:41 | `tombstoned?` checked twice (GenServer + caller) |
| 24 | from_ash.ex:76 | 3 SettingsProject signals not in catalog |
| 25 | from_ash.ex:110 | `project_data/2` returns inconsistent map shapes |
| 27 | message.ex:64 | `derive_kind` catch-all silently maps unknown to `:domain` |
| 31 | operations.ex:77 | `case Bus.send` passthrough error -- use `with` |
| 32 | operations.ex:86 | Hardcoded nil fields in return map |
| 33 | operations.ex | No `code_interface` block |
| 35 | load_task_projections.ex:32 | Task ID from `map_size` -- unstable |
| 36 | load_task_projections.ex:27 | `reduce_task/2` dispatches in body, not head |
| 37 | protocol_tracker.ex:126 | `prune_traces` O(n log n) sort vs EventStream's O(n) heap |
| 38 | runtime.ex:14-34 | `emit/2`/`emit/3` duplicate broadcast+telemetry differently |
| 39 | signals.ex:10 | `emit/2` default arg not reflected in @spec |
| 40 | task_projection.ex:14 | `:status` is `:string` not constrained atom |
| 23 | from_ash.ex:26 | Pipeline `:fail` emits `:pipeline_completed` -- can't distinguish |

## Cross-File

| # | Files | Finding |
|---|-------|---------|
| T1 | pane_scanner + agent_watchdog | 4 twin functions for done/blocked signals |
| T2 | protocol_tracker + event_stream | Same eviction problem, different algorithms |
| T3 | bus deliver_to_fleet + deliver_to_role | Same Enum.reduce-for-side-effects |
| T4 | buffer + bus | Asymmetric ETS init guards |
| T5 | operations | check_inbox + check_operator_inbox |
