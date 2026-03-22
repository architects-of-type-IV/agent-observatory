# Stage 3: Execution Plan -- Elixir Idioms Audit

Build command: `mix compile --warnings-as-errors`

42 confirmed findings grouped into 6 tasks by file dependency. All tasks are parallel (no cross-task dependencies).

## Task 1: normalizer + event_stream bugs (2 files, 3 fixes)
FILES: lib/ichor/signals/event_stream/normalizer.ex, lib/ichor/signals/event_stream.ex
CHANGES:
- normalizer.ex:105 -- `coerce_hook_type(_)` catch-all -> `:unknown` (not `:Stop`)
- normalizer.ex:109 -- `get_field` replace `||` with explicit nil check via `Map.get`
- event_stream.ex:330-340 -- `lookup_tool_start`/`track_tool_start` guards accept both atoms and strings
CONSTRAINTS: Do NOT change normalizer's coerce_hook_type/1 for atom and string inputs (only catch-all)

## Task 2: agent_watchdog + sub-modules (3 files, 8 fixes)
FILES: lib/ichor/signals/agent_watchdog.ex, lib/ichor/signals/agent_watchdog/pane_scanner.ex, lib/ichor/signals/agent_watchdog/escalation_engine.ex
CHANGES:
- pane_scanner.ex:72-91 -- merge match_done/match_blocked into `match_marker(marker, text)`
- agent_watchdog.ex:385-424 -- merge check_done_signal/check_blocked_signal into `check_pane_signal/5`
- agent_watchdog.ex:165-171 -- remove safe_emit, call Signals.emit directly
- agent_watchdog.ex:239-245 -- maybe_unpause: add `_ -> :ok` catch-all to case
- agent_watchdog.ex:352,388,408 -- extract `session_id(agent)` helper
- agent_watchdog.ex:436-453 -- `Enum.reject |> Map.new` -> `Map.filter`
- agent_watchdog.ex:101-104 -- merge two catch-all handle_info into one
- escalation_engine.ex:82 -- align fallback key with watchdog (use `:id` consistently)
CONSTRAINTS: Do NOT change escalation logic or thresholds. Only structural/idiom fixes.

## Task 3: bus.ex (1 file, 4 fixes)
FILES: lib/ichor/signals/bus.ex
CHANGES:
- L124-156 -- deliver_to_fleet/deliver_to_role: replace `Enum.reduce` for side effects with `Enum.each` + `length`
- L167-190 -- log_delivery: use monotonic integer key instead of DateTime for ETS
- L38-39 -- add Logger.warning when `:from` defaults to "system"
- L31 -- replace bare `{:ok, delivered} = deliver(...)` with proper handling
CONSTRAINTS: Do NOT change resolve/1 dispatch or delivery semantics

## Task 4: agent_lifecycle.ex + message.ex + entropy_tracker.ex + buffer.ex (4 files, 5 fixes)
FILES: lib/ichor/signals/event_stream/agent_lifecycle.ex, lib/ichor/signals/message.ex, lib/ichor/signals/entropy_tracker.ex, lib/ichor/signals/buffer.ex
CHANGES:
- agent_lifecycle.ex:66-81 -- merge handle_team_create/handle_team_delete into one function
- agent_lifecycle.ex:96 -- replace `if != ""` with pattern match
- message.ex:37-62 -- make build/3 delegate to build/4 (check meta default first)
- entropy_tracker.ex:136 -- add missing `@impl true` to catch-all handle_info
- buffer.ex:32 -- add `:ets.whereis` guard before `:ets.new` in init/1
CONSTRAINTS: Verify message.ex struct default for :meta before changing build/3

## Task 5: catalog + from_ash + signals facade + runtime (4 files, 5 fixes)
FILES: lib/ichor/signals/catalog.ex, lib/ichor/signals/from_ash.ex, lib/ichor/signals.ex, lib/ichor/signals/runtime.ex
CHANGES:
- catalog.ex -- add 3 SettingsProject signal entries (settings_project_created/updated/destroyed)
- catalog.ex:695 -- rename lookup!/1 to lookup_or_derive/1 (or make it actually raise)
- from_ash.ex:26-27 -- add comment explaining why :fail maps to :pipeline_completed (or add :pipeline_failed)
- signals.ex:10 -- add @spec for emit/1 arity (default arg)
- runtime.ex:14-34 -- extract shared broadcast+telemetry into helper for emit/2 and emit/3
CONSTRAINTS: lookup! rename requires updating ALL callers (grep first)

## Task 6: operations + preparations + task_projection + protocol_tracker + misc (6 files, 7 fixes)
FILES: lib/ichor/signals/operations.ex, lib/ichor/signals/preparations/load_task_projections.ex, lib/ichor/signals/task_projection.ex, lib/ichor/signals/protocol_tracker.ex, lib/ichor/signals/event_payload.ex, lib/ichor/signals/event_stream.ex
CHANGES:
- operations.ex:77-98 -- replace case Bus.send with `with`
- operations.ex:86-93 -- remove hardcoded nil fields
- operations.ex -- add code_interface block
- load_task_projections.ex:27 -- pattern match tool_name in function head
- task_projection.ex:14 -- change :status to :atom with one_of constraint
- protocol_tracker.ex:126 -- replace O(n log n) prune with O(n) heap pattern
- event_payload.ex -- rename file to trace_event.ex
CONSTRAINTS: event_payload.ex rename may break any `require` or `alias` referencing the old path
