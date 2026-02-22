---
type: phase
id: 1
title: decision-log-schema
date: 2026-02-22
status: pending
links:
  adr: [ADR-014]
depends_on: []
---

# Phase 1: DecisionLog Schema

## Overview

This phase defines the `Observatory.Mesh.DecisionLog` Ecto embedded schema — the universal message envelope that every agent in the Hypervisor mesh must emit. The schema captures a single decision step across six structured sections: `Meta` (tracing and causal lineage), `Identity` (agent provenance and version), `Cognition` (intent, reasoning, and entropy), `Action` (tool call and outcome status), `StateDelta` (memory and cost effects), and `Control` (HITL gate and terminal node flags). Because DecisionLog instances are validated in memory and forwarded over PubSub rather than persisted to Postgres, all sections are defined as Ecto embedded schemas rather than database tables, keeping the envelope lightweight and decoupled from any storage backend.

This phase must come first because every downstream component — the Gateway Schema Interceptor, the Topology Engine, the Entropy Computer, the Cost Heatmap, and all LiveView derivation consumers — depends on the struct contract established here. No Gateway wiring, no PubSub broadcast, and no UI component can be built until the schema module compiles cleanly, the changeset validation gates are armed, and the six UI derivation anchor fields are regression-tested by name. Phases 2 and beyond treat the `%DecisionLog{}` struct as a known, stable type; this phase is where that stability is established.

### ADR Links
- [ADR-014](../decisions/ADR-014-decision-log-envelope.md) — DecisionLog Universal Message Envelope

---

## 1.1 DecisionLog Module & Embedded Schema

- [ ] **Section 1.1 Complete**

This section creates the `Observatory.Mesh.DecisionLog` module at `lib/observatory/mesh/decision_log.ex`, defines all six inner embedded sub-schemas as inner modules, and implements the `changeset/2` function with full required-field validation and optional section handling. It covers FR-6.1 (module definition), FR-6.2 (required field validation), and FR-6.3 (optional section handling), producing the compilable foundation that all other tasks in this phase build on.

### 1.1.1 Define Observatory.Mesh.DecisionLog Module

- [ ] **Task 1.1.1 Complete**
- **Governed by:** ADR-014
- **Parent UCs:** UC-0200, UC-0201

Define the top-level Ecto embedded schema module with all six embedded sub-schemas declared as inner modules using `embedded_schema do` blocks. The module must live at `lib/observatory/mesh/decision_log.ex` under the alias `Observatory.Mesh.DecisionLog` and must not exceed 300 lines; if changeset helpers push it past that limit, extract them to `Observatory.Mesh.DecisionLog.Changesets`. Each sub-schema is embedded via `embeds_one` using inner module inline syntax so the struct fields are accessible at compile time and pattern matching against `%DecisionLog{}` is type-safe.

- [ ] 1.1.1.1 Create `lib/observatory/mesh/decision_log.ex` with `use Ecto.Schema` and `@primary_key false`, open an `embedded_schema do` block, and confirm `mix compile --warnings-as-errors` passes with an empty schema body `done_when: "mix compile --warnings-as-errors"`
- [ ] 1.1.1.2 Define `embeds_one :meta, Meta, primary_key: false` as an inline inner schema with fields: `field :trace_id, :string`, `field :timestamp, :utc_datetime`, `field :parent_step_id, :string`, `field :cluster_id, :string` `done_when: "mix compile --warnings-as-errors"`
- [ ] 1.1.1.3 Define `embeds_one :identity, Identity, primary_key: false` as an inline inner schema with fields: `field :agent_id, :string`, `field :agent_type, :string`, `field :capability_version, :string` `done_when: "mix compile --warnings-as-errors"`
- [ ] 1.1.1.4 Define `embeds_one :cognition, Cognition, primary_key: false` as an inline inner schema with fields: `field :intent, :string`, `field :reasoning_chain, {:array, :string}`, `field :confidence_score, :float`, `field :strategy_used, :string`, `field :entropy_score, :float` `done_when: "mix compile --warnings-as-errors"`
- [ ] 1.1.1.5 Define `embeds_one :action, Action, primary_key: false` as an inline inner schema with fields: `field :status, Ecto.Enum, values: [:success, :failure, :pending, :skipped]`, `field :tool_call, :string`, `field :tool_input, :string`, `field :tool_output_summary, :string` `done_when: "mix compile --warnings-as-errors"`
- [ ] 1.1.1.6 Define `embeds_one :state_delta, StateDelta, primary_key: false` as an inline inner schema with fields: `field :added_to_memory, {:array, :string}`, `field :tokens_consumed, :integer`, `field :cumulative_session_cost, :float`; and define `embeds_one :control, Control, primary_key: false` with fields: `field :hitl_required, :boolean, default: false`, `field :interrupt_signal, :string`, `field :is_terminal, :boolean, default: false` `done_when: "mix compile --warnings-as-errors"`

### 1.1.2 Changeset Validation

- [ ] **Task 1.1.2 Complete**
- **Governed by:** ADR-014
- **Parent UCs:** UC-0201, UC-0202, UC-0203

Implement `changeset/2` in `Observatory.Mesh.DecisionLog` that accepts a `%DecisionLog{}` struct and a string-keyed params map, casts all six sections via `cast_embed/3` with `required: false`, and enforces the seven required fields across the embedded changesets via `validate_required/2`. Each embedded sub-schema gets its own private changeset function (or inline `with_changes` block) that runs its own cast and validate_required calls. A payload with all required fields must pass `Ecto.Changeset.valid?/1`; a payload missing any required field must produce a changeset error on the missing field key.

- [ ] 1.1.2.1 Implement `def changeset(log, attrs)` in `Observatory.Mesh.DecisionLog` that calls `cast_embed(changeset, :meta, with: &meta_changeset/2, required: false)` for all six sections; implement private `meta_changeset/2`, `identity_changeset/2`, `cognition_changeset/2`, `action_changeset/2`, `state_delta_changeset/2`, and `control_changeset/2` helpers, each calling `cast/3` on their fields `done_when: "mix compile --warnings-as-errors"`
- [ ] 1.1.2.2 Add `validate_required(changeset, [:trace_id, :timestamp])` in `meta_changeset/2`; add `validate_required(changeset, [:agent_id, :agent_type, :capability_version])` in `identity_changeset/2`; add `validate_required(changeset, [:intent])` in `cognition_changeset/2`; add `validate_required(changeset, [:status])` in `action_changeset/2` `done_when: "mix compile --warnings-as-errors"`
- [ ] 1.1.2.3 Create `test/observatory/mesh/decision_log_test.exs` and write ExUnit tests verifying: (a) a valid full payload with all seven required fields passes `Ecto.Changeset.valid?/1`, (b) omitting `meta.trace_id` adds `{:trace_id, {"can't be blank", [validation: :required]}}` to the changeset errors, (c) omitting `identity.agent_id` adds a required error on `:agent_id`, (d) omitting `cognition.intent` when a cognition block is present adds a required error on `:intent`, (e) a payload with no `cognition`, `state_delta`, or `control` keys is still valid with those fields as nil in the applied struct `done_when: "mix test test/observatory/mesh/decision_log_test.exs"`

---

## 1.2 Action Status Enum & Causal Link Fields

- [ ] **Section 1.2 Complete**

This section verifies the `action.status` enum constraint is correctly enforced (FR-6.4), implements and tests the `parent_step_id` nil-as-root and empty-string-to-nil trimming logic (FR-6.5), and adds the `capability_version` non-empty string validation and the `major_version/1` helper for version parsing (FR-6.6). These three areas share the property that they are field-level behaviors on already-defined sub-schemas; they are grouped here because they can be verified with pure unit tests against the changeset and helper functions without any external dependencies.

### 1.2.1 Ecto.Enum for action.status

- [ ] **Task 1.2.1 Complete**
- **Governed by:** ADR-014
- **Parent UCs:** UC-0203

Verify that the `Ecto.Enum` declaration on `action.status` restricts valid values to exactly `[:success, :failure, :pending, :skipped]` and that any string outside this set produces the standard Ecto inclusion validation error. This task requires no additional code changes — the enum is defined in task 1.1.1.5 — but it requires dedicated tests that cover all four valid atoms and at least one invalid atom, providing a regression guarantee that no additional status values are added without a corresponding ADR update.

- [ ] 1.2.1.1 In `test/observatory/mesh/decision_log_test.exs`, write a parameterized test that calls `DecisionLog.changeset(%DecisionLog{}, params)` with `action.status` set to each of `"success"`, `"failure"`, `"pending"`, and `"skipped"` in turn and asserts `Ecto.Changeset.valid?(changeset) == true` and `apply_changes(changeset).action.status` equals the corresponding atom for each case `done_when: "mix test test/observatory/mesh/decision_log_test.exs"`
- [ ] 1.2.1.2 In `test/observatory/mesh/decision_log_test.exs`, write a test that calls `DecisionLog.changeset(%DecisionLog{}, params)` with `action.status` set to `"timeout"` (all other required fields present) and asserts `Ecto.Changeset.valid?(changeset) == false` and the changeset errors include `{:status, {"is invalid", [validation: :inclusion, enum: [:success, :failure, :pending, :skipped]]}}` on the action embed `done_when: "mix test test/observatory/mesh/decision_log_test.exs"`

### 1.2.2 parent_step_id Root Detection

- [ ] **Task 1.2.2 Complete**
- **Governed by:** ADR-014, ADR-017
- **Parent UCs:** UC-0204

The `meta.parent_step_id` field is optional: nil marks a DAG root, a UUID string marks a child node. A preprocessing step in `meta_changeset/2` must convert any empty string to nil before validation runs, preventing blank strings from masquerading as UUID references. The `DecisionLog.root?/1` helper provides a named predicate for callers that need to test DAG root membership without inspecting internal fields directly.

- [ ] 1.2.2.1 In `meta_changeset/2` in `lib/observatory/mesh/decision_log.ex`, add a `update_change(changeset, :parent_step_id, fn val -> if val == "", do: nil, else: val end)` step after `cast/3` and before any format validation, so that an empty string input is stored as nil; add `def root?(%__MODULE__{meta: %{parent_step_id: nil}}), do: true` and `def root?(%__MODULE__{}), do: false` to `Observatory.Mesh.DecisionLog` `done_when: "mix compile --warnings-as-errors"`
- [ ] 1.2.2.2 In `test/observatory/mesh/decision_log_test.exs`, write three tests: (a) params omitting `parent_step_id` produces a struct with `meta.parent_step_id == nil` and changeset valid; (b) params with `"parent_step_id" => ""` produces a struct with `meta.parent_step_id == nil` and no changeset error on `:parent_step_id`; (c) params with a valid UUID string produces a struct with `meta.parent_step_id` equal to that UUID string; then write two additional tests verifying `DecisionLog.root?/1` returns `true` for a struct with `meta.parent_step_id: nil` and `false` for a struct with a UUID string in `meta.parent_step_id` `done_when: "mix test test/observatory/mesh/decision_log_test.exs"`

### 1.2.3 capability_version Semver Field

- [ ] **Task 1.2.3 Complete**
- **Governed by:** ADR-014
- **Parent UCs:** UC-0205, UC-0206

The `identity.capability_version` field is a required non-empty string carrying the semver version of the schema the sending agent uses. The schema itself enforces only that the field is present and non-empty; semver format checking is delegated to the Gateway's CapabilityMap lookup (out of scope for this phase). The `major_version/1` helper extracts the major component from a semver string, enabling the Gateway and version registry to apply N-1 compatibility rules without parsing the string in multiple places.

- [ ] 1.2.3.1 Add `def major_version(%__MODULE__{identity: %{capability_version: v}}) when is_binary(v)` to `Observatory.Mesh.DecisionLog` that splits the semver string on `"."`, takes the first element, and returns it as an integer via `String.to_integer/1`; add a guard clause `def major_version(_), do: nil` for structs where identity or capability_version is nil `done_when: "mix compile --warnings-as-errors"`
- [ ] 1.2.3.2 In `test/observatory/mesh/decision_log_test.exs`, write tests verifying: (a) `DecisionLog.major_version/1` returns `2` when `identity.capability_version` is `"2.1.0"`; (b) returns `1` when capability_version is `"1.0.0"`; (c) returns `nil` when the identity section is nil; also write a changeset test that passes an empty string for `capability_version` and asserts the changeset error includes `{:capability_version, {"can't be blank", [validation: :required]}}` `done_when: "mix test test/observatory/mesh/decision_log_test.exs"`

---

## 1.3 Entropy Score Overwrite & Deserialization

- [ ] **Section 1.3 Complete**

This section implements the Gateway-side entropy score overwrite helper on the `DecisionLog` struct (FR-6.7), the `from_json/1` deserialization entry point that accepts a decoded JSON map and returns a validated struct or error changeset (FR-6.8), and the regression test suite for the six UI derivation anchor fields (FR-6.9). These three tasks complete the schema module's public API surface: by the end of this section, `DecisionLog` exposes `changeset/2`, `root?/1`, `major_version/1`, `put_gateway_entropy_score/2`, and `from_json/1`, and all six anchor fields are regression-locked by name.

### 1.3.1 Gateway Authoritative entropy_score

- [ ] **Task 1.3.1 Complete**
- **Governed by:** ADR-014, ADR-018
- **Parent UCs:** UC-0206

The `cognition.entropy_score` submitted by an agent is treated as informational only. The Gateway must overwrite it with the value computed by `Observatory.Mesh.EntropyComputer.compute/1` before any PubSub broadcast. Placing this transformation as a named function on `DecisionLog` rather than inline in the Gateway keeps the schema module as the single point of authority for struct mutation and makes the overwrite step independently testable without spinning up the full Gateway pipeline.

- [ ] 1.3.1.1 Add `def put_gateway_entropy_score(%__MODULE__{cognition: nil} = log, _score), do: log` and `def put_gateway_entropy_score(%__MODULE__{cognition: cognition} = log, score) when is_float(score)` to `Observatory.Mesh.DecisionLog`, where the second clause returns `%{log | cognition: %{cognition | entropy_score: score}}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 1.3.1.2 In `test/observatory/mesh/decision_log_test.exs`, write two tests: (a) build a `%DecisionLog{}` struct with `cognition.entropy_score: 0.9` via `apply_changes/1`, call `DecisionLog.put_gateway_entropy_score(log, 0.15)`, and assert the returned struct has `cognition.entropy_score == 0.15`; (b) build a `%DecisionLog{}` struct with `cognition: nil`, call `DecisionLog.put_gateway_entropy_score(log, 0.15)`, and assert the returned struct still has `cognition: nil` and no error is raised `done_when: "mix test test/observatory/mesh/decision_log_test.exs"`

### 1.3.2 JSON Deserialization

- [ ] **Task 1.3.2 Complete**
- **Governed by:** ADR-014
- **Parent UCs:** UC-0207, UC-0208

The `from_json/1` function provides a named entry point for the Gateway controller to cast a decoded JSON map (string-keyed, as produced by `Jason.decode!/1` or `Plug.Parsers`) into a validated `%DecisionLog{}` struct. It wraps `changeset/2` and `apply_changes/1`, returning a two-tuple `{:ok, struct}` or `{:error, changeset}` so callers can pattern-match on the result without inspecting changeset internals directly. This mirrors the convention used elsewhere in the codebase for schema-to-struct pipelines.

- [ ] 1.3.2.1 Add `def from_json(attrs) when is_map(attrs)` to `Observatory.Mesh.DecisionLog` that calls `changeset(%__MODULE__{}, attrs)`, then returns `{:ok, Ecto.Changeset.apply_changes(cs)}` if `cs.valid?` is true or `{:error, cs}` if `cs.valid?` is false `done_when: "mix compile --warnings-as-errors"`
- [ ] 1.3.2.2 In `test/observatory/mesh/decision_log_test.exs`, write three tests: (a) `DecisionLog.from_json/1` with a valid string-keyed map returns `{:ok, %DecisionLog{}}` and the struct has all required fields populated; (b) `from_json/1` with a map containing `"action" => %{"status" => "timeout"}` returns `{:error, changeset}` where `changeset.valid? == false` and the changeset errors include an `:status` inclusion error; (c) `from_json/1` with a map missing `"meta"` entirely returns `{:error, changeset}` where the errors include a `:trace_id` required error `done_when: "mix test test/observatory/mesh/decision_log_test.exs"`

### 1.3.3 UI Field Derivation Contract

- [ ] **Task 1.3.3 Complete**
- **Governed by:** ADR-014
- **Parent UCs:** UC-0208

The six UI derivation anchor fields — `meta.parent_step_id`, `cognition.reasoning_chain`, `cognition.entropy_score`, `state_delta.cumulative_session_cost`, `control.hitl_required`, and `control.is_terminal` — must be accessible on any `%DecisionLog{}` struct without raising, even when the parent embedded section is nil. These regression tests lock in the field names so that any rename causes an immediate test failure and alerts the developer to increment the major version in `identity.capability_version` and update all downstream UI consumers.

- [ ] 1.3.3.1 In `test/observatory/mesh/decision_log_test.exs`, write a test named `"UI derivation anchor fields are accessible when embedded sections are nil"` that builds a minimal `%DecisionLog{}` via `DecisionLog.from_json/1` with only the seven required fields, extracts the struct from `{:ok, log}`, and asserts that accessing `log.meta.parent_step_id`, `log.cognition`, `log.state_delta`, and `log.control` does not raise; then asserts `is_nil(log.cognition)`, `is_nil(log.state_delta)`, and `is_nil(log.control)`; and uses `Map.get(log.cognition || %{}, :reasoning_chain)`, `Map.get(log.cognition || %{}, :entropy_score)`, `Map.get(log.state_delta || %{}, :cumulative_session_cost)`, `Map.get(log.control || %{}, :hitl_required)`, and `Map.get(log.control || %{}, :is_terminal)` to confirm nil-safe access patterns produce nil without raising `done_when: "mix test test/observatory/mesh/decision_log_test.exs"`
- [ ] 1.3.3.2 In `test/observatory/mesh/decision_log_test.exs`, write a test named `"UI derivation anchor field names are declared in the schema"` that asserts `Observatory.Mesh.DecisionLog.Meta.__schema__(:fields)` includes `:parent_step_id`; `Observatory.Mesh.DecisionLog.Cognition.__schema__(:fields)` includes `:reasoning_chain` and `:entropy_score`; `Observatory.Mesh.DecisionLog.StateDelta.__schema__(:fields)` includes `:cumulative_session_cost`; and `Observatory.Mesh.DecisionLog.Control.__schema__(:fields)` includes `:hitl_required` and `:is_terminal`; so that renaming any anchor field breaks this test and forces a major version review `done_when: "mix test test/observatory/mesh/decision_log_test.exs"`

---
