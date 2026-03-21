# Control Domain Audit

## Preamble: How this audit is structured

For each file I answer:
1. **Module name + purpose** (one line)
2. **Public functions**: name, arity, inputs, outputs, what it does
3. **Anti-pattern?** Is this duplicating Ash DSL capabilities?
4. **Logic that belongs in an Ash action?**
5. **Could this be an embedded resource?**
6. **Cross-module shape duplication**

---

## `lib/ichor/control.ex` — `Ichor.Control` (Ash Domain)

**Purpose:** Ash Domain that also acts as a hand-written wrapper module — 27 functions.

**Anti-pattern finding: 21 of 27 functions are pure 1-line wrappers.**

Every function listed below directly delegates to a resource's `code_interface`. This is the primary anti-pattern the audit was commissioned to find.

| Domain function | What it calls | `code_interface` define already exists? |
|---|---|---|
| `list_agents/0` | `Agent.all!()` | YES — `define(:all)` on Agent |
| `list_active_agents/0` | `Agent.active!()` | YES — `define(:active)` on Agent |
| `list_alive_teams/0` | `Team.alive!()` | YES — `define(:alive)` on Team |
| `list_teams/0` | `Team.all!()` | YES — `define(:all)` on Team |
| `get_unread/1` | `Agent.get_unread(agent_id)` | YES — `define(:get_unread, args: [:agent_id])` |
| `mark_read/2` | `Agent.mark_read(agent_id, message_id)` | YES — `define(:mark_read, ...)` |
| `list_blueprints/0` | `TeamBlueprint.read!(load: [...])` | YES — `define(:read)` on TeamBlueprint |
| `list_agent_types/0` | `AgentType.sorted!()` | YES — `define(:sorted)` on AgentType |
| `blueprint_by_id/1` | `TeamBlueprint.by_id(id)` | YES — `define(:by_id, args: [:id])` |
| `blueprint_by_name/1` | `TeamBlueprint.by_name(name)` | YES — `define(:by_name, args: [:name])` |
| `create_blueprint/1` | `TeamBlueprint.create(attrs)` | YES — `define(:create)` |
| `update_blueprint/2` | `TeamBlueprint.update(blueprint, attrs)` | YES — `define(:update)` |
| `destroy_blueprint/1` | `TeamBlueprint.destroy(blueprint)` | YES — `define(:destroy)` |
| `agent_type/1` | `AgentType.by_id(id)` | YES — `define(:by_id, args: [:id])` |
| `create_agent_type/1` | `AgentType.create(attrs)` | YES — `define(:create)` |
| `update_agent_type/2` | `AgentType.update(...)` | YES — `define(:update)` |
| `destroy_agent_type/1` | `AgentType.destroy(...)` | YES — `define(:destroy)` |
| `list_due_webhook_deliveries/0` | `WebhookDelivery.due_for_delivery!()` | Need to verify |
| `list_dead_letters_for_agent/1` | `WebhookDelivery.dead_letters_for_agent!(agent_id)` | Need to verify |
| `list_all_dead_letters/0` | `WebhookDelivery.all_dead_letters!()` | Need to verify |
| `mark_webhook_delivered/1` | `WebhookDelivery.mark_delivered(delivery)` | Need to verify |
| `schedule_webhook_retry/2` | `WebhookDelivery.schedule_retry(...)` | Need to verify |
| `mark_webhook_dead/2` | `WebhookDelivery.mark_dead(...)` | Need to verify |
| `schedule_cron_once/3` | `CronJob.schedule_once(...)` | Need to verify |
| `list_cron_jobs_for_agent/1` | `CronJob.for_agent!(agent_id)` | Need to verify |
| `list_all_cron_jobs/0` | `CronJob.all_scheduled!()` | Need to verify |
| `list_due_cron_jobs/1` | `CronJob.due!(now)` | Need to verify |
| `get_cron_job/1` | `CronJob.get(id)` | Need to verify |
| `reschedule_cron_job/2` | `CronJob.reschedule(...)` | Need to verify |
| `complete_cron_job/1` | `CronJob.complete(job)` | Need to verify |

**The exception:** `enqueue_webhook_delivery/1` has real logic — it pattern-matches a map to extract fields and adds an optional `webhook_id` key. This is not a pure delegate but could be replaced with a `code_interface` define with explicit argument list.

**Verdict on `control.ex`:** The domain module has become a redirection layer for code_interface functions that already exist. All 27 wrapper functions should be removed. Callers should use the resource code_interface directly (via `Ichor.Control.Agent.all!()` etc.) or, if a single stable entry point is needed, a thin `Ichor.Control` function calling `Ash.read!` on the domain is acceptable — but only for genuinely domain-level orchestration, not single-resource reads.

---

## `lib/ichor/control/agent.ex` — `Ichor.Control.Agent` (Ash Resource, no data layer)

**Purpose:** Runtime view of a living agent. No persistence — data comes from Registry via `LoadAgents` preparation.

**Public functions via code_interface:**
- `all/0` → reads all agents from Registry
- `active/0` → filtered: `status != :ended`
- `in_team/1` → filtered: `team_name == arg`
- `launch/0` → generic action: delegates to `AgentLaunch.spawn/1`
- `spawn/1(id:)` → generic action: delegates to `FleetSupervisor` / `TeamSupervisor`
- `pause_agent/1(agent_id:)` → generic action: `AgentProcess.pause/1`
- `resume_agent/1(agent_id:)` → generic action: `AgentProcess.resume/1`
- `terminate_agent/1(agent_id:)` → generic action: terminates via supervisor lookup
- `get_unread/1(agent_id:)` → generic action: `AgentProcess.get_unread/1` + mapping
- `mark_read/2(agent_id:, message_id:)` → generic action: no-op (destructive read)
- `send_message/2(agent_id:, content:)` → generic action: `Ichor.MessageRouter.send/1`
- `update_instructions/2(agent_id:, instructions:)` → generic action: `AgentProcess.update_instructions/2`

**Anti-patterns found:**

1. **`get_unread` action contains inline data mapping logic** (lines 228–241). The `Enum.map` that converts raw agent messages to a `%{"id" => ..., "from" => ...}` string-keyed map is pure transformation. This belongs in a separate `MessagePresenter` or `MessageView` module, not inside an Ash action `run` anonymous function.

2. **`spawn` action contains branching logic** that decides whether to use `FleetSupervisor` or `TeamSupervisor` and creates teams if missing. This logic is already extracted into the `spawn_in_fleet/2` private function — acceptable — but `spawn_in_fleet` contains a side effect (creates a team if absent) that is not obviously visible at the action boundary. This is an implicit team creation side effect.

3. **`terminate_agent` action** hardcodes the termination routing logic (team vs. fleet) inline. This is already done identically in `Registration.terminate/1`. **Duplicate logic** — same branching pattern in two places.

4. **`maybe_put/3` private helper** is generic enough to warrant a shared utility, but is fine as a private function here.

**Verdict:** This resource is well-structured. The generic actions pattern is idiomatic for BEAM-backed resources. The main issues are: (a) inline mapping in `get_unread`, (b) duplicate termination routing vs. `Registration.terminate/1`.

---

## `lib/ichor/control/team.ex` — `Ichor.Control.Team` (Ash Resource, no data layer)

**Purpose:** Runtime view of a living team. No persistence — data from Registry/events via `LoadTeams` preparation.

**Public functions via code_interface:**
- `all/0` → reads all teams from Registry + events
- `alive/0` → filtered: `dead? == false`
- `create_team/1(name:)` → delegates to `FleetSupervisor.create_team/1`
- `disband/1(name:)` → delegates to `FleetSupervisor.disband_team/1`
- `spawn_member/2(team_name:, agent_id:)` → delegates to `TeamSupervisor.spawn_member/2`

**Anti-patterns found:**

1. **`create_team` action** accepts `strategy`, `project`, `description` arguments but only `name` and `strategy` are passed to `FleetSupervisor`. The `description` argument is accepted but **silently dropped** — it never reaches any downstream storage.

2. **`spawn_member` action** is a near-duplicate of `Agent.spawn` action logic — same `TeamSupervisor.spawn_member` call with overlapping argument shapes. The agent spawn path is accessible from two different resources (`Agent.spawn` + `Team.spawn_member`) with different argument signatures.

**Verdict:** Structurally clean. The silent `description` drop is a bug-level oversight. The duplicate spawn entry point creates two code paths with divergent argument handling.

---

## `lib/ichor/control/team_blueprint.ex` — `Ichor.Control.TeamBlueprint` (Ash Resource, SQLite)

**Purpose:** Persisted team blueprint with relationships to `AgentBlueprint`, `SpawnLink`, `CommRule`.

**Public functions via code_interface:**
- `create/1` — accepts attrs + `agent_blueprints`, `spawn_links`, `comm_rules` as managed relationships
- `read/0` — default read
- `update/2` — accepts same attrs + managed relationships
- `destroy/1` — default destroy
- `by_id/1(id:)` — get by UUID with relationships loaded
- `by_name/1(name:)` — get by name with relationships loaded

**Anti-patterns found:**

1. **`list_blueprints` in domain** calls `TeamBlueprint.read!(load: [:agent_blueprints, :spawn_links, :comm_rules])` — but `by_id` and `by_name` already have `prepare(build(load: ...))`. There is no `list` action that auto-loads relationships. The domain wrapper adds the `load:` option because the base `read` action doesn't include it. The fix: add a dedicated `read :list` action with `prepare(build(load: [...]))` so callers don't need to remember to add `load:` options.

2. **`by_id` uses `argument(:id, :uuid)` + `filter(expr(id == ^arg(:id)))`** — this is the standard pattern but could use `get_by: [:id]` shorthand if the resource had a primary read action with identity-based lookup.

**Verdict:** Resource is well-structured. The `load:` omission in the base `read` action is a UX gap.

---

## `lib/ichor/control/agent_blueprint.ex` — `Ichor.Control.AgentBlueprint` (Ash Resource, SQLite)

**Purpose:** Persisted agent node within a team blueprint. Holds canvas position + config.

**Public functions via code_interface:**
- `create/1`, `read/0`, `update/2`, `destroy/1`

**Anti-patterns found:**

1. **No `by_id` read action.** Since `AgentBlueprint` is managed entirely through `TeamBlueprint` relationships (via `manage_relationship`), direct lookup may not be needed. Acceptable for a sub-resource.

2. **`team_blueprint_id` in create `accept` list.** When managing through a relationship, Ash normally sets the FK automatically. Having `team_blueprint_id` in the explicit `accept` list allows direct assignment bypassing relationship management. This is either intentional or a redundancy.

**Verdict:** Clean sub-resource. The `team_blueprint_id` in accept is worth questioning.

---

## `lib/ichor/control/agent_type.ex` — `Ichor.Control.AgentType` (Ash Resource, SQLite)

**Purpose:** Reusable agent archetype / template. Defines defaults for agent parameters.

**Public functions via code_interface:**
- `create/1`, `read/0`, `update/2`, `destroy/1`
- `by_id/1(id:)` — get by UUID
- `sorted/0` — reads sorted by `sort_order asc, name asc`

**Anti-patterns found:**

1. **`sorted` action uses `prepare(build(sort: [...]))`.** This is a preparation-level sort, not a sort declared in the action DSL's `sort` block. The pattern is correct but `build(sort: [...])` in a preparation is less explicit than `sort sort_order: :asc, name: :asc` declared directly in the action. Either approach works; `build` in prepare is idiomatic for dynamic composition.

2. **`defaults_for_model` / template derivation logic does not exist on this resource.** The `AgentBlueprint` resource duplicates all field names with identical defaults (capability: "builder", model: "sonnet", etc.). There is no "derive blueprint defaults from type" function on `AgentType`. The `BlueprintState.agent_type_agent/3` function does this mapping in a plain module — acceptable but creates a third location where these defaults are defined.

**Verdict:** Clean. The triple-definition of defaults (AgentType, AgentBlueprint, BlueprintState) is worth consolidating.

---

## `lib/ichor/control/spawn_link.ex` — `Ichor.Control.SpawnLink` (Ash Resource, SQLite)

**Purpose:** Spawn hierarchy link between two agent blueprint slots.

**Public functions via code_interface:** `create/1`, `read/0`, `destroy/1`

**Anti-patterns found:** None significant. Simple junction resource managed via `TeamBlueprint` relationship. The `update` action exists in `actions` but is **not exposed** in `code_interface` — minor inconsistency.

---

## `lib/ichor/control/comm_rule.ex` — `Ichor.Control.CommRule` (Ash Resource, SQLite)

**Purpose:** Communication rule (allow/deny/route) between two blueprint agent slots.

**Public functions via code_interface:** `create/1`, `read/0`, `destroy/1`

**Anti-patterns found:** Same as `SpawnLink` — `update` action defined but not in `code_interface`.

**Cross-module shape match:** `SpawnLink` and `CommRule` have identical structural patterns: `from_slot`, `to_slot`, `belongs_to :team_blueprint`, same actions, same code_interface gap. They share a shape.

---

## `lib/ichor/control/presets.ex` — `Ichor.Control.Presets`

**Purpose:** Compile-time preset configurations for Workshop canvas + spawn ordering logic.

**Public functions:**
- `names/0` → `[String.t()]` — returns preset map keys
- `fetch/1(name)` → `{:ok, map()} | :error` — lookup by name
- `apply/2(state, name)` → `map()` — merges preset into LiveView state
- `spawn_order/2(agents, spawn_links)` → `[map()]` — depth-first ordering of agents

**Anti-patterns found:**

1. **`fetch/1` is a trivial wrapper over `Map.fetch/2`.** The body is `case Map.fetch(@presets, name) do {:ok, preset} -> {:ok, preset}; :error -> :error end`. This is pure redirection — the function adds zero value. Should be `def fetch(name), do: Map.fetch(@presets, name)`.

2. **`apply/2` operates on LiveView state map keys (`ws_team_name`, `ws_strategy`, etc.).** This creates coupling between the preset module and the LiveView's internal state shape. The preset module should return a normalized struct, and the LiveView should merge it. Currently `Presets.apply/2` knows about `ws_*` prefixed keys — this is a layer violation.

3. **`spawn_order/2` is pure graph traversal logic** — well-placed here, though it could live in a dedicated `SpawnGraph` module if the algorithm grows.

**Verdict:** The `apply/2` coupling to LiveView state keys is the main concern. `fetch/1` is trivially simplifiable.

---

## `lib/ichor/control/blueprint_state.ex` — `Ichor.Control.BlueprintState`

**Purpose:** Pure state machine for Workshop canvas — all LiveView state transitions.

**Public functions:**
- `defaults/0` → `map()` — initial state
- `clear/1(state)` → `map()` — reset to defaults
- `add_agent/2(state, attrs)` → `t()` — add agent to canvas
- `select_agent/2(state, id)` → `t()` — set selected agent
- `move_agent/4(state, id, x, y)` → `t()` — update canvas position
- `update_agent/3(state, id, params)` → `t()` — apply param changes to agent
- `remove_agent/2(state, id)` → `t()` — remove agent + its links/rules
- `add_spawn_link/3(state, from, to)` → `t()` — add link (idempotent)
- `remove_spawn_link/2(state, index)` → `t()` — remove link by index
- `add_comm_rule/4(state, from, to, policy)` → `t()` — add rule (idempotent)
- `remove_comm_rule/2(state, index)` → `t()` — remove rule by index
- `update_team/2(state, params)` → `t()` — apply team-level changes
- `apply_blueprint/2(state, blueprint)` → `t()` — load persisted blueprint into canvas
- `new_agent/2(state, attrs)` → `agent()` — construct agent map with auto-positioning
- `agent_type_agent/3(state, type, index)` → `agent()` — build agent from AgentType record
- `to_persistence_params/1(state)` → `map()` — serialize canvas state for blueprint create/update

**Anti-patterns found:**

1. **`update_agent/3` uses string key access (`Map.get(params, "name", ...)`)** while internally the agent maps use atom keys. This is the `from_struct/params` shape boundary — the function accepts raw LiveView form params (string keys) and converts to internal shape (atom struct keys). This is acceptable but should be documented clearly. Currently no `@spec` indicates string vs atom keys.

2. **The `agent_to_ash/1` and `ash_to_agent/1` private helpers** perform bidirectional translation between the canvas agent shape (`id:`, `x:`, `y:`) and the Ash resource shape (`slot:`, `canvas_x:`, `canvas_y:`). These are essentially a manual codec between two representations of the same data. If the resource used `x` and `y` instead of `canvas_x` and `canvas_y`, this translation disappears.

3. **`to_persistence_params/1`** knows the exact Ash `accept` list of `TeamBlueprint.create`. Any change to the resource schema requires updating this function. This is a soft coupling.

4. **`safe_list/1`** guards against non-list relationship values. This suggests the resource sometimes returns `%Ash.NotLoaded{}` for relationships — indicating callers aren't consistently ensuring relationships are loaded before calling `apply_blueprint/2`.

**Verdict:** This is a well-written pure module. The main design issue is the schema translation (`id`/`x`/`y` vs `slot`/`canvas_x`/`canvas_y`) creating a translation layer that could be eliminated by aligning the resource attribute names with the canvas map shape.

---

## `lib/ichor/control/persistence.ex` — `Ichor.Control.Persistence`

**Purpose:** Domain-facing save/load/delete operations for blueprints, coordinating `BlueprintState` + `Control` domain.

**Public functions:**
- `save_blueprint/2(blueprint_id, state)` → `{:ok, map()} | {:error, term()}` — upsert blueprint
- `load_blueprint/2(state, id)` → `{:ok, map()} | {:error, term()}` — fetch + apply to state
- `delete_blueprint/1(id)` → `:ok | {:error, term()}` — fetch + destroy

**Anti-patterns found:**

1. **All three functions call `Control.blueprint_by_id/1`** which is itself a wrapper over `TeamBlueprint.by_id/1` which is a `code_interface` define. This is a two-hop indirection: `Persistence` → `Control.blueprint_by_id` → `TeamBlueprint.by_id`. With `Control` wrappers removed, these would go directly to `TeamBlueprint.by_id/1`.

2. **`save_blueprint/2` contains upsert logic** — if `id` is nil, create; else fetch + update; if fetch fails, create again. This is a retry-on-not-found pattern. The retry branch (`save_blueprint(nil, state)`) could loop if creation also fails. An Ash `upsert` action on `TeamBlueprint` would handle this more robustly.

3. **`delete_blueprint/1` fetches to get the struct** only so it can pass it to `destroy`. This is the standard Ash pattern (you need the record to destroy it), but `TeamBlueprint.destroy/1` accepting an ID directly would simplify this.

**Verdict:** This module is small and correct. Its main weakness is the two-hop domain indirection and the retry-on-not-found upsert pattern.

---

## `lib/ichor/control/runtime_view.ex` — `Ichor.Control.RuntimeView`

**Purpose:** Pure projection helpers for merging teams/agents from multiple sources for display.

**Public functions:**
- `resolve_selected_team/2(current, teams)` → `String.t() | nil` — default to single team
- `find_team/2(teams, name)` → `map() | nil` — find by name in list
- `merge_display_teams/3(teams, agents, tmux_sessions)` → `[map()]` — merge BEAM teams with tmux-discovered teams
- `build_agent_lookup/1(agents)` → `map()` — multi-key lookup map (agent_id, session_id, short_name)

**Anti-patterns found:**

1. **`build_agent_lookup/1` calls `Map.from_struct/1`** on an Ash struct — this converts struct keys to a plain map. The Ash rule is to use dot access only. This is a presentation-layer concern (converting to JSON-friendly format) happening in a logic module. Should move to a `Presenter` module.

2. **`dedup_by_status/1` private function** uses an `Enum.reduce` with a Map accumulator to deduplicate by status preference. This is a keyed dedup pattern that appears in multiple places — same pattern as `build_registry_lookup` in `LoadTeams`, and `build_agent_lookup` in this module. **Shape duplication across three modules.**

3. **`inferred_team_health/1` private function** has identical logic to `to_resource/1` in `LoadTeams` (both compute team health from member healths by checking for `:critical`, `:warning`, `:healthy`). **Logic duplication across two modules.** Should be extracted to `AgentHealth.compute_team_health/1` or similar.

**Verdict:** Good pure module. Two duplication issues worth consolidating.

---

## `lib/ichor/control/runtime_query.ex` — `Ichor.Control.RuntimeQuery`

**Purpose:** Shared read-model query helpers for fleet data, crossing team/event/task boundaries.

**Public functions:**
- `find_team_member/2(teams, agent_id)` → `map() | nil` — find member in team list
- `find_agent_entry/3(id, teams, events)` → `map()` — find agent or synthesize from events
- `find_active_task/2(agent_name, swarm)` → `map() | nil` — find in-progress task
- `list_tasks_for_teams/1(teams)` → `[map()]` — gather tasks from `TeamStore`
- `format_team/1(team)` → `map()` — serialize team to string-keyed map

**Anti-patterns found:**

1. **`format_team/1` produces a string-keyed map** — this is a presentation/serialization concern mixed into a query module. Belongs in `Presentation` or a dedicated presenter.

2. **`find_agent_entry/3` falls back through `Lookup.find_agent/1`** and then `Presentation.short_id/1`. This function calls three different layers: team list search, event search, registry lookup, presentation formatting. It mixes concerns.

3. **`find_team_member/2` and `find_agent_entry/3` both do `Enum.flat_map(&1.members)`** — same traversal pattern duplicated within the same module.

**Verdict:** This module is a grab-bag of query helpers that span too many concerns. The team member search, event lookup, task lookup, and presentation serialization should be in separate modules.

---

## `lib/ichor/control/lookup.ex` — `Ichor.Control.Lookup`

**Purpose:** Shared agent lookup and display name helpers.

**Public functions:**
- `find_agent/1(query)` → `struct() | nil` — multi-field agent search
- `agent_session_id/1(agent)` → `String.t() | nil` — extract session_id or fall back to agent_id
- `agent_display_name/1(agent)` → `String.t() | nil` — derive display name

**Anti-patterns found:**

1. **`find_agent/1` calls `Control.list_agents()`** — this is a full registry scan on every lookup. For single-agent lookup, this is O(n) where n is fleet size. A direct `AgentProcess.lookup/1` would be O(1) via Registry.

2. **`agent_display_name/1` returns `String.t() | nil`** — the spec allows nil but `short_name || name || agent_id` should always produce a non-nil value if `agent_id` is non-nil. The return type is over-wide.

3. **`agent_session_id/1`** is a 1-line helper that could be inlined at all callsites without loss of clarity.

**Verdict:** The `find_agent` O(n) scan via `Control.list_agents()` is the main concern. Should use `AgentProcess.lookup/1` directly.

---

## `lib/ichor/control/analysis/agent_health.ex` — `Ichor.Control.Analysis.AgentHealth`

**Purpose:** Pure health computation from event lists. Failure rate, stuck detection, loop detection.

**Public functions:**
- `compute_agent_health/2(events, now)` → `map()` — returns `{health, issues, failure_rate, stuck?, loops}`
- `calculate_failure_rate/1(events)` → `float()` — ratio of failed to total tool uses

**Anti-patterns found:**

1. **Return type is `map()`** — should be a typed struct `AgentHealth.t()` for the result. Currently callers pattern-match on `health_data.health`, `health_data.issues`, `health_data.failure_rate` — all dot access on a map. This is fine but a struct would make the contract explicit.

2. **`build_issues/4` and `classify_health/3`** each use `then/2` chains for conditional accumulation. The pattern `|> then(fn issues -> if condition, do: [item | issues], else: issues end)` is idiomatic but verbose compared to list comprehensions or a dedicated accumulator function.

**Verdict:** Clean pure module. The map-vs-struct return type is the only design question.

---

## `lib/ichor/control/analysis/session_eviction.ex` — `Ichor.Control.Analysis.SessionEviction`

**Purpose:** Pure TTL-based eviction of stale sessions from event lists.

**Public functions:**
- `evict_stale/2(events, now)` → `[event]` — remove sessions with no activity within TTL

**Anti-patterns found:** None. Well-designed pure module with clear input/output shapes.

---

## `lib/ichor/control/analysis/queries.ex` — `Ichor.Control.Analysis.Queries`

**Purpose:** Pure derivation of active sessions and topology from raw events.

**Public functions:**
- `active_sessions/2(events, opts)` → `[map()]` — group events by session, derive session maps
- `topology/3(all_sessions, teams, now)` → `{[map()], [map()]}` — derive topology nodes + edges

**Anti-patterns found:**

1. **`import IchorWeb.DashboardFormatHelpers`** — this module imports web-layer helpers (`session_duration_sec/1`) into a pure data module. This creates a dependency from `ichor/control/analysis` to `ichor_web`. **Layer violation**: the analysis module should not depend on the web layer. `session_duration_sec/1` should be inlined or moved to a shared utility.

2. **`import IchorWeb.DashboardSessionHelpers`** — same concern for `short_model_name/1`.

3. **`session_node/3`** produces a map with display-oriented keys (`label`, `duration`, `cwd: Path.basename(cwd)`). This is presentation logic inside a data module. The topology function produces a view-model, not a domain model.

**Verdict:** The cross-layer imports are the critical issue. `Analysis.Queries` depends on the web layer, which inverts the dependency. The fix is to either move the format helpers to a shared pure module or remove the formatting from the analysis layer entirely and let the web layer format.

---

## `lib/ichor/control/views/preparations/load_agents.ex` — `Ichor.Control.Views.Preparations.LoadAgents`

**Purpose:** Ash `Preparation` that populates agent read actions from the BEAM Registry.

**Key behavior:** Calls `AgentProcess.list_all()` to get raw registry metadata, then constructs `Agent` structs via `struct!/2`.

**Anti-patterns found:**

1. **`normalize_status/1`** maps `:paused` → `:idle`. This means `AgentProcess` status `:paused` is hidden from consumers — the Ash `Agent` struct can never have status `:paused`. If a consumer needs to distinguish paused from idle, this lossy conversion is a bug.

2. **Hardcoded `health: :healthy`** for all agents. Every agent comes back as healthy regardless of actual health. The health computation (`AgentHealth.compute_agent_health/2`) exists but is not called here — it's only used in `LoadTeams`. This means the `Agent` resource's `health` attribute is always `:healthy` for standalone agent reads.

3. **`event_count: 0` and `tool_count: 0`** — these attributes exist on the resource but are always 0 in this preparation. Dead attributes.

**Verdict:** The health hardcoding and lost `:paused` status are correctness gaps.

---

## `lib/ichor/control/views/preparations/load_teams.ex` — `Ichor.Control.Views.Preparations.LoadTeams`

**Purpose:** Ash `Preparation` that builds team records from events + BEAM Registry.

This is the most complex preparation — ~260 lines with multi-source merging.

**Anti-patterns found:**

1. **`to_resource/1`** duplicates the team health rollup logic from `RuntimeView.inferred_team_health/1`. Both functions contain the same `cond` block checking `:critical`, `:warning`, `:healthy`. **Logic duplication.**

2. **`derive_from_events/1`** and the extract helper chain is complex event parsing. This logic could be extracted to `Analysis.Queries.active_teams_from_events/1` for testability.

3. **`build_registry_lookup/0`** contains a `reduce` with status-preference deduplication — identical pattern to `RuntimeView.dedup_by_status/1` and `build_agent_lookup/1`. **Same algorithm duplicated in three modules.**

4. **`enrich_members/4`** calls `AgentHealth.compute_agent_health/2` per member — correct, but the `derive_member_status/3` function inside this preparation duplicates status derivation logic that also appears in `LoadAgents`.

**Verdict:** This preparation is doing too much. The event parsing, registry merging, health computation, and dead-team detection should each be in dedicated modules. The status/health duplication with `LoadAgents` and `RuntimeView` is the most concrete refactor target.

---

## `lib/ichor/control/agent_process.ex` — `Ichor.Control.AgentProcess` (GenServer)

**Purpose:** The live agent process. Holds mailbox, state, and backend transport.

**Public functions:**
- `start_link/1(opts)` → `GenServer.on_start()`
- `child_spec/1(opts)` → `Supervisor.child_spec()` — custom restart strategy for liveness-polled agents
- `send_message/2(agent_id, message)` → `:ok` — cast to mailbox
- `get_state/1(agent_id)` → `t()` — synchronous state read
- `get_unread/1(agent_id)` → `[map()]` — destructive read, clears unread
- `pause/1(agent_id)` → `:ok` — buffers messages
- `resume/1(agent_id)` → `:ok` — delivers buffered messages
- `update_instructions/2(agent_id, instructions)` → `:ok` — cast
- `update_metadata/2(agent_id, fields)` → `:ok` — cast, merges into `metadata` field
- `update_fields/2(agent_id, fields)` → `:ok` — cast, merges into Registry entry
- `alive?/1(agent_id)` → `boolean()`
- `list_all/0` → `[{String.t(), map()}]`
- `lookup/1(agent_id)` → `{pid(), map()} | nil`

**Anti-patterns found:**

1. **`update_metadata/2` vs `update_fields/2`** — two functions with identical signatures that write to different targets (`state.metadata` vs Registry). The naming is unclear. `update_metadata` mutates the GenServer state; `update_fields` mutates the Registry entry. These are very different operations with misleadingly similar names.

2. **`handle_cast({:update_fields, fields})` only updates Registry** — the GenServer state is not updated. If a consumer calls `get_state/1` after `update_fields/2`, they get stale data. This is a correctness gap if `get_state` and Registry are expected to be consistent.

3. **`via/1` private function** returns a Registry via tuple. Called in every public function. This is a standard pattern.

**Verdict:** The `update_metadata`/`update_fields` naming confusion is the main issue. Otherwise well-structured GenServer.

---

## `lib/ichor/control/agent_process/registry.ex` — `Ichor.Control.AgentProcess.Registry`

**Purpose:** Registry projection helpers — builds and updates agent metadata entries.

**Public functions:**
- `build_initial_meta/3(id, state, meta)` → `map()` — construct initial registry entry
- `fields_from_event/1(event)` → `map()` — derive registry update fields from an event
- `update/2(id, fields)` → `{term(), term()} | :error` — merge fields into registry entry

**Anti-patterns found:**

1. **`fields_from_event/1`** hardcodes `status: :active` on every event — same issue as in `LoadAgents`. Any event causes the agent to be marked active, even `SessionEnd` events.

2. **`merge_current_tool/2`** matches on both atom and string versions of hook event types (`:PreToolUse` and `"PreToolUse"`). This suggests inconsistent typing upstream — events sometimes have atom and sometimes string hook types. This is a data quality issue.

**Verdict:** The dual-type matching for hook event types points to an upstream normalization gap. Should be fixed at the ingestion boundary, not patched here.

---

## `lib/ichor/control/agent_process/delivery.ex` — `Ichor.Control.AgentProcess.Delivery`

**Purpose:** Message normalization and backend dispatch.

**Public functions:**
- `normalize/2(msg, to)` → `map()` — two clauses: map input and string input
- `deliver/2(backend, msg)` → `:ok` — dispatch to tmux, ssh_tmux, or webhook
- `broadcast/2(agent_id, msg)` → `:ok` — emit signal

**Anti-patterns found:**

1. **`deliver/2` has duplicate ssh_tmux clauses** — one matching `%{type: :ssh_tmux, address: address}` and another matching `%{type: :ssh_tmux, session: session, host: host}`. These are two different ssh_tmux config shapes. The inconsistency means callers can configure ssh_tmux in two ways. Should be normalized to one shape.

**Verdict:** Clean module. The dual ssh_tmux shape is an API inconsistency.

---

## `lib/ichor/control/agent_process/lifecycle.ex` — `Ichor.Control.AgentProcess.Lifecycle`

**Purpose:** Liveness check scheduling and lifecycle signal emission.

**Public functions:**
- `schedule_liveness_check/0` → `reference()` — `Process.send_after` for `:check_liveness`
- `tmux_alive?/1(backend)` → `{boolean(), String.t()}` — check tmux target
- `terminate_backend/1(backend)` → `:ok | {:error, term()}` — kill tmux window/session
- `broadcast/1(event)` → `:ok` — emit lifecycle signal

**Anti-patterns found:** None. Clean pure-ish module with clear boundaries.

---

## `lib/ichor/control/agent_process/mailbox.ex` — `Ichor.Control.AgentProcess.Mailbox`

**Purpose:** Incoming message routing — normalize, buffer, broadcast, route to backend.

**Public functions:**
- `apply_incoming_message/2(state, message)` → `AgentProcess.t()` — full pipeline
- `deliver_unread/1(state)` → `AgentProcess.t()` — flush buffered messages on resume
- `route_message/2(message, state)` → `AgentProcess.t()` — buffer or deliver

**Anti-patterns found:**

1. **`route_message/2` buffers all messages into `state.unread`** regardless of whether the agent is active. For active agents, the message is both delivered to the backend AND added to `unread`. This means `unread` grows unboundedly for active agents. The `@max_message_buffer 200` cap is only applied to `state.messages`, not to `state.unread`.

2. **`@doc false`** on `route_message/2` — the function is public (`def`, not `defp`) with `@doc false`. Since this is a public API used within the same module's `apply_incoming_message`, it should be `defp`.

**Verdict:** The unbounded `unread` growth and the `@doc false` on a public function are both correctness/style issues.

---

## `lib/ichor/control/fleet_supervisor.ex` — `Ichor.Control.FleetSupervisor` (DynamicSupervisor)

**Purpose:** Root supervisor for all teams and standalone agents.

**Public functions:**
- `start_link/1(opts)` → `Supervisor.on_start()`
- `create_team/1(opts)` → `DynamicSupervisor.on_start_child() | {:error, :already_exists}`
- `disband_team/1(team_name)` → `:ok | {:error, :not_found}`
- `spawn_agent/1(opts)` → `DynamicSupervisor.on_start_child()`
- `terminate_agent/1(agent_id)` → `:ok | {:error, :not_found}`

**Anti-patterns found:**

1. **`disband_team/1` emits signals** (`Ichor.Signals.emit(:team_disbanded, ...)`) in two branches (success and not-found). This is the correct pattern — side effects at boundaries.

2. **Signal emission on `:not_found`** is unusual. Broadcasting a "disbanded" signal when the team was never found could confuse subscribers into thinking disbandment succeeded. A separate `:team_disband_failed` signal might be cleaner.

**Verdict:** Clean supervisor. The signal-on-failure pattern is debatable.

---

## `lib/ichor/control/team_supervisor.ex` — `Ichor.Control.TeamSupervisor` (DynamicSupervisor)

**Purpose:** Team-level supervisor. Holds agent processes as children.

**Public functions:**
- `start_link/1(opts)` → `Supervisor.on_start()`
- `spawn_member/2(team_name, agent_opts)` → `DynamicSupervisor.on_start_child()`
- `terminate_member/2(team_name, agent_id)` → `:ok | {:error, :not_found}`
- `members/1(team_name)` → child specs list
- `member_count/1(team_name)` → `non_neg_integer()`
- `member_ids/1(team_name)` → `[String.t()]`
- `exists?/1(team_name)` → `boolean()`
- `list_all/0` → `[{String.t(), map()}]`

**Anti-patterns found:**

1. **`member_count/1` calls `members/1` and takes `length`** — this triggers `DynamicSupervisor.which_children/1` which is a synchronous call to the supervisor process. For display-only use (showing count in UI), this is acceptable but adds overhead.

2. **`TeamSupervisor` has a struct definition** (`defstruct [:name, :project, ...]`) that is never constructed. The struct exists but is unused — dead code.

**Verdict:** The unused struct definition is dead code. Otherwise well-structured.

---

## `lib/ichor/control/host_registry.ex` — `Ichor.Control.HostRegistry` (GenServer)

**Purpose:** Tracks available BEAM nodes for remote agent spawning.

**Public functions:**
- `start_link/1`, `list_hosts/0`, `get_host/1(node)`, `register_host/2(node, metadata)`, `remove_host/1(node)`, `available?/1(node)`, `local_host/0`

**Anti-patterns found:**

1. **`available?/1` bypasses the GenServer** — it calls `Node.list()` directly, making it inconsistent with the registry state. A node could be in the registry as `:disconnected` but `available?` would return `true` if it's in `Node.list()`. The registry state and the runtime truth can diverge.

2. **`node_hostname/1` uses `Atom.to_string(node) |> String.split("@") |> List.last()`** — this pattern appears twice (once in `node_hostname/1` and once in `hostname/0`). The private helper could be a single clause that's reused.

**Verdict:** The `available?/1` consistency gap between registry state and `Node.list()` is a correctness issue for distributed scenarios.

---

## `lib/ichor/control/lifecycle.ex` — `Ichor.Control.Lifecycle`

**Purpose:** Public boundary for team lifecycle. Single `defdelegate`.

**Public functions:**
- `launch_team/1(spec)` → `{:ok, String.t()} | {:error, term()}` — delegates to `TeamLaunch.launch/1`

**Anti-patterns found:** This module is 13 lines and contains only a `defdelegate`. The module adds no value — callers could call `Ichor.Control.Lifecycle.TeamLaunch.launch/1` directly. This module exists to create a named public boundary, which is intentional, but if there's only one function it's marginal.

---

## `lib/ichor/control/lifecycle/agent_launch.ex` — `Ichor.Control.Lifecycle.AgentLaunch`

**Purpose:** Single-agent launch: validates, writes tmux scripts, creates tmux window, registers BEAM process.

**Public functions:**
- `init_counter/0` → `:ok` — initialize atomic spawn counter
- `spawn/1(opts)` → `{:ok, map()} | {:error, term()}` — dispatch local or remote
- `spawn_local/1(opts)` → `{:ok, map()} | {:error, term()}` — full local launch pipeline

**Anti-patterns found:**

1. **`build_spec/1` sets `agent_id: window_name`** — the agent ID is derived from the window name which includes an atomic counter. This means agent IDs are not stable across restarts. If the process dies and restarts, it will get a different `agent_id`. This is likely intentional for tmux-backed ephemeral agents but worth noting.

2. **`spawn/1` dispatches on `opts[:host]`** — the `%{host: target}` pattern match comes first. If `host` is `Node.self()`, it should take the local path. Currently it would call `HostRegistry.available?(Node.self())` which calls `Node.list()` and would not find itself there (Node.self() is not in Node.list()). This could cause a local spawn to fail if the caller sets `host: Node.self()`.

3. **`@agents_dir` is a module attribute** derived from `Path.expand("~/.ichor/agents")` at compile time. This means the directory is baked in at compile time. If the app runs as a different user in production, this may not expand correctly.

**Verdict:** The `host: Node.self()` edge case and compile-time path expansion are correctness concerns.

---

## `lib/ichor/control/lifecycle/team_launch.ex` — `Ichor.Control.Lifecycle.TeamLaunch`

**Purpose:** Multi-agent team launch: creates tmux session, all windows, registers all agents.

**Public functions:**
- `launch/1(spec)` → `{:ok, String.t()} | {:error, term()}`
- `launch_into_existing_session/2(spec, session)` → `:ok | {:error, term()}`

**Anti-patterns found:**

1. **`create_windows/3` and `register_agents/1` both use `Enum.reduce_while`** — they halt on first failure. This means partial launches are possible: if window 3 fails to create, windows 1 and 2 exist but are unregistered. No rollback mechanism. This could leave orphaned tmux windows.

2. **`write_agent_files/1`** is also a `reduce_while` with the same partial-write risk.

**Verdict:** The lack of rollback on partial launch is an operational concern. Not a code smell per se, but a design gap.

---

## `lib/ichor/control/lifecycle/registration.ex` — `Ichor.Control.Lifecycle.Registration`

**Purpose:** BEAM process registration for agents — creates `AgentProcess` under the correct supervisor.

**Public functions:**
- `ensure_team/1(name)` → `:ok | {:error, term()}`
- `register/2(spec, tmux_target)` → `{:ok, map()} | {:error, term()}`
- `resolve_tmux_target/1(agent_id)` → `String.t() | nil`
- `terminate/1(agent_id)` → `:ok | {:error, :not_found}`

**Anti-patterns found:**

1. **`do_register/2`** has two identical result map shapes (one for success, one for `:already_started`) that are very similar. Factoring out the result map construction would reduce duplication.

2. **`terminate/1`** duplicates the same team-routing logic as `Agent.terminate_agent` action's `run` function. **Logic duplication in three places**: `Agent.terminate_agent`, `Registration.terminate/1`, and `FleetSupervisor.terminate_agent`. The canonical place is `Registration.terminate/1` — both other locations should delegate here.

---

## `lib/ichor/control/lifecycle/agent_spec.ex` and `lifecycle/team_spec.ex`

**Purpose:** Typed structs for launch specifications. Both use `@enforce_keys` and `new/1` constructors.

**Anti-patterns found:**

1. **Both `AgentSpec.new/1` and `TeamSpec.new/1` implement the same `fetch!/2` and `fetch/3` private helpers** with identical code. This 6-line helper is duplicated across the two modules.

2. **`fetch/3` uses `Map.get(attrs, key, Map.get(attrs, to_string(key), default))`** — this accepts both atom and string keys. This exists to handle LiveView params (string-keyed) without conversion. But a cleaner approach would be to normalize keys at the boundary before calling `new/1`.

**Verdict:** The duplicated `fetch!/2` / `fetch/3` helpers could be extracted to a `Ichor.Control.Lifecycle.SpecBuilder` shared utility.

---

## `lib/ichor/control/lifecycle/cleanup.ex` — `Ichor.Control.Lifecycle.Cleanup`

**Purpose:** Stop agents, kill sessions, clean orphaned teams and tmux sessions, run GC script.

**Public functions:**
- `stop_agent/1(agent_id)` → `:ok | {:error, term()}`
- `kill_session/1(session)` → `:ok | {:error, term()}`
- `cleanup_prompt_dir/1(dir)` → `:ok`
- `cleanup_orphaned_teams/2(active_teams, prefix)` → `:ok`
- `cleanup_orphaned_tmux_sessions/2(active_sessions, prefix)` → `:ok`
- `trigger_gc/2(team_name, path)` → `{:ok, String.t()} | {:error, String.t()}`

**Anti-patterns found:**

1. **`@gc_script` path** is hardcoded to `~/.claude/skills/dag/scripts/gc.sh`. This is a dependency on a specific local tool path from a non-lifecycle module. If the Claude skills are absent, `trigger_gc/2` silently fails with an error tuple.

2. **`stop_agent/1`** calls `Registration.resolve_tmux_target/1` + `Registration.terminate/1` + `EventBuffer.remove_session/1` in sequence. The first two are both via `Registration` (good). The `EventBuffer.remove_session/1` call crosses domains.

**Verdict:** The GC script path hardcoding is an ops concern. The `EventBuffer` cross-domain call in `stop_agent/1` is a boundary question.

---

## `lib/ichor/control/lifecycle/tmux_launcher.ex` — `Ichor.Control.Lifecycle.TmuxLauncher`

**Purpose:** Thin wrapper over `System.cmd("tmux", ...)` for session/window management.

**Public functions:**
- `create_session/4`, `create_window/4`, `kill_session/1`, `send_exit/1`, `available?/1`, `list_sessions/0`

**Anti-patterns found:** None. Clean thin wrapper with consistent `:ok | {:error, reason}` returns.

---

## `lib/ichor/control/lifecycle/tmux_script.ex` — `Ichor.Control.Lifecycle.TmuxScript`

**Purpose:** Writes prompt and launch shell script files for tmux-backed agents.

**Public functions:**
- `write_agent_files/5(base_dir, file_name, prompt, model, capability)` → `{:ok, map()} | {:error, term()}`
- `cleanup_dir/1(dir)` → `:ok`
- `render_script/3(prompt_path, model, capability)` → `String.t()`

**Anti-patterns found:** None. Pure file I/O wrapped cleanly.

---

## `lib/ichor/control/tmux_helpers.ex` — `Ichor.Control.TmuxHelpers`

**Purpose:** Shared tmux socket path, capability-to-role mapping, CLI arg building.

**Public functions:**
- `tmux_args/0` → `[String.t()]` — socket path args
- `capability_to_role/1(cap)` → `atom()`
- `capabilities_for/1(cap)` → `[atom()]`
- `add_permission_args/2(args, cap)` → `[String.t()]`

**Anti-patterns found:**

1. **`capability_to_role/1` and `capabilities_for/1`** both branch on the same set of string capabilities. If a new capability is added, both functions must be updated. These could be unified into a single data structure (a map of capability → `{role, [capabilities]}`).

2. **`@ichor_socket` path** — same compile-time path concern as in `AgentLaunch`.

**Verdict:** The dual-function maintenance for capability mapping is a minor fragility.

---

## `lib/ichor/control/team_spec_builder.ex` — `Ichor.Control.TeamSpecBuilder`

**Purpose:** Translates Workshop LiveView state into a `TeamSpec` for launch.

**Public functions:**
- `build_from_state/2(state, opts)` → `TeamSpec.t()`
- `session_name/1(team_name)` → `String.t()`
- `prompt_dir/1(team_name)` → `String.t()`
- `prompt_root_dir/0` → `String.t()`

**Anti-patterns found:**

1. **`build_from_state/2` accepts builder callbacks as opts** (`prompt_builder`, `agent_metadata_builder`, `window_name_builder`, `agent_id_builder`). This is a flexible design but the defaults for these callbacks are private functions within the same module. The callback pattern allows override from test or MES, but the default implementations are tightly coupled to the Workshop state shape.

2. **`slug/1`** is duplicated — the same `String.downcase |> String.replace |> String.trim("-")` pattern appears in `TeamSpecBuilder` and potentially in other modules.

3. **`prompt_for_agent/2`** builds a multi-section instruction prompt. This is prompt engineering / content generation logic sitting in a builder module. Should be extracted to a dedicated `AgentPrompt` module.

**Verdict:** The prompt generation logic is the main concern. It combines builder orchestration with content generation.

---

## CROSS-MODULE SHAPE DUPLICATION SUMMARY

The following identical patterns appear in multiple modules:

### 1. Agent status deduplication by `:active` preference
Same `Enum.reduce` that prefers `:active` entries when deduplicating by key:
- `RuntimeView.dedup_by_status/1`
- `LoadTeams.build_registry_lookup/0`
- `RuntimeView.build_agent_lookup/1` (via `dedup_by_status`)

### 2. Team health rollup from member healths
Same `cond` checking `:critical` → `:warning` → `:healthy` → `:unknown`:
- `RuntimeView.inferred_team_health/1`
- `LoadTeams.to_resource/1`

### 3. Agent termination routing (team vs fleet)
Same `case state.team do nil -> FleetSupervisor; team -> TeamSupervisor end`:
- `Agent.terminate_agent` action run function
- `Registration.terminate/1`

The canonical version is `Registration.terminate/1`. The other two should delegate to it.

### 4. Spec builder `fetch!/2` / `fetch/3` atom+string key lookup
- `AgentSpec.new/1`
- `TeamSpec.new/1`

### 5. `maybe_put/3` or `maybe_merge/3` conditional map merge
- `Agent` resource (`maybe_put/3`)
- `AgentProcess.Registry` (`maybe_merge/3`)

These are identical in purpose, different in name.

---

## DOMAIN WRAPPER FUNCTIONS — DISPOSITION TABLE

All 27 wrapper functions in `control.ex` and their correct replacement:

| Current | Should be | Notes |
|---|---|---|
| `Control.list_agents()` | `Agent.all!()` | code_interface defined |
| `Control.list_active_agents()` | `Agent.active!()` | code_interface defined |
| `Control.list_alive_teams()` | `Team.alive!()` | code_interface defined |
| `Control.list_teams()` | `Team.all!()` | code_interface defined |
| `Control.get_unread(id)` | `Agent.get_unread!(id)` | code_interface defined |
| `Control.mark_read(aid, mid)` | `Agent.mark_read!(aid, mid)` | code_interface defined |
| `Control.list_blueprints()` | Need `TeamBlueprint.list!()` with auto-load | add `read :list` action |
| `Control.list_agent_types()` | `AgentType.sorted!()` | code_interface defined |
| `Control.blueprint_by_id(id)` | `TeamBlueprint.by_id(id)` | code_interface defined |
| `Control.blueprint_by_name(n)` | `TeamBlueprint.by_name(n)` | code_interface defined |
| `Control.create_blueprint(attrs)` | `TeamBlueprint.create(attrs)` | code_interface defined |
| `Control.update_blueprint(bp, attrs)` | `TeamBlueprint.update(bp, attrs)` | code_interface defined |
| `Control.destroy_blueprint(bp)` | `TeamBlueprint.destroy(bp)` | code_interface defined |
| `Control.agent_type(id)` | `TeamBlueprint.by_id(id)` | code_interface defined |
| `Control.create_agent_type(attrs)` | `AgentType.create(attrs)` | code_interface defined |
| `Control.update_agent_type(at, attrs)` | `AgentType.update(at, attrs)` | code_interface defined |
| `Control.destroy_agent_type(at)` | `AgentType.destroy(at)` | code_interface defined |
| `Control.enqueue_webhook_delivery(attrs)` | Move logic into `WebhookDelivery` action | real logic present |
| `Control.list_due_webhook_deliveries()` | `WebhookDelivery.due_for_delivery!()` | code_interface likely |
| `Control.list_dead_letters_for_agent(id)` | `WebhookDelivery.dead_letters_for_agent!(id)` | code_interface likely |
| `Control.list_all_dead_letters()` | `WebhookDelivery.all_dead_letters!()` | code_interface likely |
| `Control.mark_webhook_delivered(d)` | `WebhookDelivery.mark_delivered(d)` | code_interface likely |
| `Control.schedule_webhook_retry(d, a)` | `WebhookDelivery.schedule_retry(d, a)` | code_interface likely |
| `Control.mark_webhook_dead(d, a)` | `WebhookDelivery.mark_dead(d, a)` | code_interface likely |
| `Control.schedule_cron_once(...)` | `CronJob.schedule_once(...)` | code_interface likely |
| `Control.list_cron_jobs_for_agent(id)` | `CronJob.for_agent!(id)` | code_interface likely |
| `Control.list_all_cron_jobs()` | `CronJob.all_scheduled!()` | code_interface likely |
| `Control.list_due_cron_jobs(now)` | `CronJob.due!(now)` | code_interface likely |
| `Control.get_cron_job(id)` | `CronJob.get(id)` | code_interface likely |
| `Control.reschedule_cron_job(j, t)` | `CronJob.reschedule(j, t)` | code_interface likely |
| `Control.complete_cron_job(j)` | `CronJob.complete(j)` | code_interface likely |

---

## RANKED FINDINGS BY SEVERITY

### Critical (correctness gaps)
1. **Agent health always `:healthy` in `LoadAgents`** — health attribute is meaningless for standalone agents
2. **`status: :active` hardcoded on every event in `Registry.fields_from_event`** — agents never become `:idle` or `:ended` via event updates
3. **Termination logic duplicated** in `Agent.terminate_agent`, `Registration.terminate/1` — divergence risk
4. **`unread` unbounded growth** in `Mailbox.route_message` for active agents
5. **`available?/1` inconsistent** with `HostRegistry` state in `HostRegistry`

### High (design anti-patterns)
6. **21+ wrapper functions in `control.ex`** — entire domain module is a redirection layer
7. **`Analysis.Queries` imports web layer** — inverted dependency
8. **Team health rollup duplicated** in `RuntimeView` and `LoadTeams`
9. **Dedup-by-status duplicated** in `RuntimeView` (×2) and `LoadTeams`
10. **`update_metadata` vs `update_fields`** naming confusion in `AgentProcess`

### Medium (maintenance cost)
11. **`BlueprintState` field name mismatch** (`id`/`x`/`y` vs `slot`/`canvas_x`/`canvas_y`)
12. **`AgentSpec.new`/`TeamSpec.new` duplicate `fetch!` helpers**
13. **`capability_to_role` and `capabilities_for` maintain parallel maps**
14. **`Presets.apply/2` coupled to LiveView `ws_*` state keys**
15. **`TeamLaunch` no rollback on partial launch**
16. **`TeamSupervisor` has unused struct definition**

### Low (style/minor)
17. **`Presets.fetch/1` wraps `Map.fetch/2` with no added value**
18. **`route_message/2` is public with `@doc false`** — should be `defp`
19. **`SpawnLink` and `CommRule` have `update` action not in code_interface**
20. **`TeamBlueprint.read` action doesn't auto-load relationships** — callers pass `load:` manually
21. **`Lifecycle.ex` is a single-function boundary module** — marginal value

---

The audit is complete. All 40 files in `lib/ichor/control/` have been analyzed.