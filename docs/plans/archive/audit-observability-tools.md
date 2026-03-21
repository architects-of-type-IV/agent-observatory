## Audit: Observability and Tools Domains

**Note:** Plan mode was active during audit execution, preventing direct file writes at that time. This file captures the complete audit findings.

---

### Mandatory docs first

`mix usage_rules.docs Ash.CodeInterface` returned only the one-liner summary (no detailed DSL docs available). The key point confirmed: `code_interface` on a Domain is not a standard Ash DSL block — code_interface blocks live on Resources, and Domain-level access happens through resource-generated functions or direct `Ash.*` calls through the domain.

---

## OBSERVABILITY DOMAIN

### `Ichor.Observability` — The Domain Module

**Finding 1 (Style/Maintenance):** All 8 public functions are one-liner delegates to resource `code_interface` functions. These hand-written wrappers are valid Ash but create a synchronization burden — every new resource action needs a matching domain function. The correct Ash idiomatic pattern is `defdelegate` to the resource code_interface, or just accept that callers use the domain via `Ash.read!(Resource, domain: Ichor.Observability)`. The current pattern is not wrong, but it will drift.

The only caller that uses these domain functions correctly is `Archon.Messages` (calls `Observability.list_recent_messages/0`). All LiveView callers also go through the domain correctly.

### `Event` — SQLite-backed hook event store

- `code_interface define(:read)` — only one action exposed. Correct.
- No named filter arguments on `:read`. Callers pass raw Ash opts. Fine for internal use.

### `Session` — SQLite-backed session lifecycle

**Finding 6 (Gap):** No `code_interface` block. Two meaningful actions (`:create` with upsert, `:mark_ended`) are not exposed. Sessions must be written through raw `Ash.create/2` calls bypassing the domain. Should have at minimum `define :create` and `define :mark_ended`.

### `Message` / `Task` / `Error` — Virtual `DataLayer.Simple` projection resources

**Finding 7 (Bug):** `Observability.Task` has `simple_notifiers: [Ichor.Signals.FromAsh]` but is a `DataLayer.Simple` virtual resource with only a read action. `FromAsh` fires on Ash writes (create/update/destroy through the data layer). This resource is never written through Ash — it is populated by a preparation. The notifier will **never fire**. The `signal_for(Ichor.Observability.Task, :create)` and `signal_for(Ichor.Observability.Task, :update)` clauses in `from_ash.ex` are dead code.

**Finding 8:** `Error.by_tool` is a generic action whose `run` closure calls `__MODULE__.recent!()` and then does group/sort/map. This is pure list transformation disguised as an Ash action. It belongs as a domain function or in `EventAnalysis`.

### `EventAnalysis` — Pure transformation module

Clean. Correctly a plain Elixir module, not an Ash resource. `tool_analytics/1`, `timeline/1`, and `pair_tool_events/1` are all pure.

**Finding 10 (Minor):** `build_timeline_blocks/1` duplicates the pre/post pairing logic from `pair_tool_events/1`. They compute the same `post_events` map and iterate `pre_events` identically. `build_timeline_blocks` adds idle-gap injection on top. `pair_tool_events` could be extracted and reused. Low priority.

### `Janitor` — GenServer purge cycle

**Finding 11:** Uses raw Ecto (`from(e in "events", where: ...)`) bypassing Ash. Ash notifiers do not fire on these deletes. Intentional for performance but undocumented as an exception. The pattern is defensible for a background purger but should be documented.

### Preparations: `LoadErrors`, `LoadMessages`, `LoadTasks`

**Finding 12 (High):** The `list_events/0` private function — 12 lines of EventBuffer dynamic module resolution — is **identical** in all three preparation modules. This 3x duplication is the single most actionable cleanup in the Observability domain. Extract to `Ichor.Observability.EventBufferReader` or `Ichor.EventBuffer.Reader`.

**Finding 13:** The config key `:ichor_activity` may be a legacy umbrella artifact. If ICHOR is a single OTP app now, this should be `:ichor`.

---

## TOOLS DOMAIN

### `Ichor.Tools` — The Domain Module

Structurally sound. `AshAi` extension used correctly. `tools do` block wires 21 resource modules to 67 named tools. `validate_config_inclusion?: false` is intentional (non-data domain). No issues.

### Cross-Cutting Tool Findings

**Finding 16/27/53 (Medium — Duplication):** `maybe_put/3` is defined identically in `Agent.Spawn` and `Archon.Mes`:
```elixir
defp maybe_put(map, _key, nil), do: map
defp maybe_put(map, _key, ""), do: map
defp maybe_put(map, _key, []), do: map
defp maybe_put(map, key, value), do: Map.put(map, key, value)
```
`GenesisFormatter.put_if/3` only handles nil (not empty string/list). `Archon.Control.spawn_agent` implements the same pattern via `Enum.reject`. Three implementations of "omit nil/empty from map." Should be unified in `GenesisFormatter` or a shared `Tools.Helpers` module.

**Finding 28/50 (High — Safety):** Two uses of `String.to_existing_atom`:
- `GenesisNodes.advance_node`: `String.to_existing_atom(input.arguments.status)`
- `Archon.Mes.list_projects`: `String.to_existing_atom(status_str)`

Both should use a validated mapping (as `GenesisGates` correctly does with `@valid_modes` + `Map.fetch!`). Note that `GenesisGates` crashes with `KeyError` on unknown values (Finding 34) — validated mapping with a graceful error return is the correct pattern.

**Finding 41 (Low):** Nil-filtering is implemented three different ways across the tool modules. Choose one and stick with it.

### Agent Tools — By Module

**`Inbox`:** Sound. `agent_send_message` returns nil-valued keys `"via"` and `"error"` — should omit nils. `check_inbox` silently swallows errors.

**`Tasks`:** `get_tasks` silently returns empty list when `team_name` is nil. Agent gets zero results with no feedback.

**`Memory`:** Clean delegation. Well-typed error messages to LLM callers.

**`Recall` / `Archival`:** Clean. `page` argument should use `default:` in DSL rather than `|| 0` in closure.

**`Agents`:** Clean. Extra_block normalization (`b["label"] || b[:label]`) is correctly placed at the tool/MCP boundary.

**`Spawn`:** Finding 26 — `stop_agent` only pattern-matches `{:ok, ...}` variants. Safe now because AgentControl.stop always returns `{:ok, ...}`, but brittle.

**`GenesisNodes`:**
- Finding 28: unsafe atom conversion in `advance_node`
- **Finding 29 (High):** `gate_report/1` encodes pipeline readiness rules (`ready_for_define = adrs > 0 and accepted_adrs > 0`). This is business logic — it belongs on the `Node` resource as a calculation (or in the `Projects` domain), not in a tool presentation facade.

**`GenesisArtifacts`:**
- Finding 31: `@valid_statuses` map redeclares the ADR status enum values. Should derive from the resource enum type.

**`GenesisGates`:**
- Finding 34: `Map.fetch!(@valid_modes, args.mode)` crashes with `KeyError` on unknown mode. Should return `{:error, "unknown mode: #{args.mode}"}`.

**`GenesisRoadmap`:**
- Finding 35: `Ash.load(phase, sections: [tasks: [:subtasks]])` called directly inside a run closure. Should be encapsulated in `Projects.load_phase_with_hierarchy/1`.

**`DagExecution`:**
- Finding 37: `complete_job` makes two separate DB reads (available jobs + all jobs) that could be collapsed into a domain-level function.
- `format_ash_error/1` is a useful private helper unique to this module — worth moving to `GenesisFormatter` for reuse.

### Archon Tools — By Module

**`Agents`:**
- Finding 38: `agent.channels[:tmux] || agent.tmux_session` — dual-path access suggesting a struct refactor was partially applied.
- Finding 39: `format_agent/1` likely duplicates formatting in LiveView components.

**`Control`:**
- Finding 40: Archon `spawn_agent` has all args `allow_nil?: false`; Agent `spawn_agent` has most optional. Intentional difference, should be documented.
- **Finding 42 (High):** `sweep/0` always returns `%{"swept" => true}` for a no-op. False positive to LLM callers.

**`Events`:**
- **Finding 43 (Medium — Performance):** `agent_events` fetches ALL events from EventBuffer then filters by session_id in-memory. O(n) full scan. EventBuffer should support filtered access.

**`Teams`:** Clean. Single responsibility.

**`Messages`:** Correctly uses `Observability` domain API. Good pattern to follow.

**`System`:** Clean. `tmux_sessions` has the dual-path channels access issue (Finding 48).

**`Manager`:** Clean. Minimal delegation.

**`Memory`:** Clean. `default:` values set at DSL level — correct pattern.

**`Mes`:**
- Finding 50: unsafe atom conversion
- Finding 51: `GenServer.call` with try/catch on `:exit` — correct defensive pattern
- Finding 52: `check_operator_inbox` wraps everything in broad `try/rescue` returning `{:ok, []}` — silent error swallow
- Finding 53: duplicate `maybe_put/3`
- Finding 54: `create_project` has 13 required arguments where empty string = "none". Normalization belongs in the resource create action.

### Support Modules

**`AgentControl`:**
- Finding 55: `stop/1` always returns `{:ok, ...}`. Callers cannot distinguish success from "not found" via pattern matching — must inspect the result map. Unconventional contract.
- Correctly a plain Elixir module (no Ash). Good placement.

**`GenesisFormatter`:**
- **Finding 57 (Critical):** `to_map/2` emits a signal (`Ichor.Signals.emit(:genesis_artifact_created, ...)`) as a side effect inside a utility/projection function. A function named `to_map` must be pure. The signal belongs in the resource notifier or in the domain action that calls `Projects.create_*`. Every caller of `to_map` triggers a signal, including callers using it for list projections or updates.
- Finding 58: `infer_node_id/1` walks `node_id || phase_id || section_id || task_id`. Fragile schema topology encoding. Silent nil return for unknown artifact types.
- `split_csv`, `parse_enum`, `stringify`, `put_if`, `summarize` — all pure, correct, reusable.

**`Profiles`:**
- Finding 59: No compile-time check that profile lists match registered tools. Silent omission if a tool is registered in Tools.ex but not added to the profile.

---

## Priority Summary

| Priority | Count | Key Issues |
|---|---|---|
| Critical | 2 | Dead `FromAsh` notifier on virtual resource; signal side-effect in `GenesisFormatter.to_map` |
| High | 5 | Triplicated `list_events/0` in preparations; 2x unsafe `String.to_existing_atom`; gate logic in tool layer; false-positive `sweep` response |
| Medium | 4 | Duplicated `maybe_put/3`; `Map.fetch!` crash on unknown mode; O(n) EventBuffer scan; missing `Session` code_interface |
| Low | 7 | `Error.by_tool` in wrong layer; hand-written domain wrappers; silent empty results; fragile `infer_node_id`; various minor style issues |
