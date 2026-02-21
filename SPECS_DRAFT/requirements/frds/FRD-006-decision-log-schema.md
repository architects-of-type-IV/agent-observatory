---
id: FRD-006
title: DecisionLog Schema Functional Requirements
date: 2026-02-22
status: draft
source_adr: [ADR-014]
related_rule: []
---

# FRD-006: DecisionLog Schema

## Purpose

The DecisionLog is the universal message envelope transmitted by every agent in the Hypervisor network. It carries a structured, versioned record of a single decision step: who made it, why, what action was taken, and what effect it had on memory or cost. Every message entering the Gateway MUST conform to this schema before it is broadcast to the rest of the system.

The schema is implemented as an Ecto embedded schema rather than a database table because DecisionLog instances are received as HTTP payloads, validated in memory, and forwarded over PubSub. They are never persisted directly to Postgres. This design keeps the message envelope lightweight and decoupled from any particular storage backend.

## Functional Requirements

### FR-6.1: Module Location and Struct Definition

The DecisionLog schema MUST be defined in `lib/observatory/mesh/decision_log.ex` under the module `Observatory.Mesh.DecisionLog`. The module MUST use `use Ecto.Schema` with `embedded_schema do` at the top level and MUST define six embedded sub-schemas as inner modules: `Meta`, `Identity`, `Cognition`, `Action`, `StateDelta`, and `Control`. Each sub-schema MUST be embedded via `embeds_one`. The module MUST NOT exceed 300 lines. If helper functions cause the module to approach that limit, changeset helpers MAY be extracted to `Observatory.Mesh.DecisionLog.Changesets`.

**Positive path**: A call to `Observatory.Mesh.DecisionLog.changeset(%DecisionLog{}, params)` succeeds and returns a valid `%Ecto.Changeset{}` with all six embedded sections populated or nil according to the input.

**Negative path**: If the module is defined anywhere outside `lib/observatory/mesh/`, the zero-warnings build policy requires that `mix compile --warnings-as-errors` catches any module alias mismatches and fails the build.

---

### FR-6.2: Required Field Validation

The changeset function MUST enforce the following fields as required and MUST add Ecto validation errors when any are absent or nil: `meta.trace_id` (string, UUID v4 format), `meta.timestamp` (`:utc_datetime`), `identity.agent_id` (string), `identity.agent_type` (string), `identity.capability_version` (string, semver format), `cognition.intent` (string), and `action.status` (enum atom). Validation MUST use `validate_required/2` on each embedded changeset. A DecisionLog missing any required field MUST NOT be considered valid and MUST NOT be forwarded by the Gateway.

**Positive path**: A payload containing all seven required fields passes `Ecto.Changeset.valid?/1` returning `true`, and the resulting struct is forwarded to the appropriate PubSub topic.

**Negative path**: A payload omitting `meta.trace_id` causes `Ecto.Changeset.valid?/1` to return `false`. The Gateway reads the changeset errors, constructs a `SchemaViolationEvent` with `violation_reason: "missing required field: meta.trace_id"`, and returns HTTP 422 to the caller.

---

### FR-6.3: Optional Section Handling

All six embedded sections MUST be cast with `cast_embed/3` using the `optional: true` flag, meaning the presence of any sub-schema block in the incoming payload is not itself required. When the `cognition` section is entirely absent from the payload, the resulting struct MUST have `cognition: nil`. The Gateway MUST skip entropy alerting when `cognition` is nil and MUST NOT raise on a nil cognition field. Optional scalar fields within present sections (for example `meta.cluster_id`, `cognition.reasoning_chain`, `cognition.confidence_score`, `cognition.strategy_used`, `cognition.entropy_score`, `action.tool_call`, `action.tool_input`, `action.tool_output_summary`, `state_delta.added_to_memory`, `state_delta.tokens_consumed`, `state_delta.cumulative_session_cost`, `control.hitl_required`, `control.interrupt_signal`, `control.is_terminal`) MAY be nil without failing validation.

**Positive path**: A minimal payload containing only the seven required fields produces a valid struct with `cognition: nil`, `state_delta: nil`, and `control: nil`. The Gateway proceeds with entropy alerting disabled.

**Negative path**: A payload containing a `cognition` block but omitting `cognition.intent` causes `valid?/1` to return `false` because `intent` is required within the `Cognition` embedded changeset. The Gateway rejects the message with HTTP 422.

---

### FR-6.4: action.status Enum Values

The `action.status` field MUST use `Ecto.Enum` restricted to exactly four atoms: `:success`, `:failure`, `:pending`, and `:skipped`. Any value outside this set MUST cause the changeset to add a validation error on `action.status`. The enum MUST be defined inline within the `Action` embedded schema as `field :status, Ecto.Enum, values: [:success, :failure, :pending, :skipped]`. No additional status atoms MAY be introduced without a corresponding ADR update.

**Positive path**: A payload with `"status": "pending"` in the action block produces `action.status: :pending` in the resulting struct and passes validation.

**Negative path**: A payload with `"status": "timeout"` causes an Ecto validation error `{"is invalid", [validation: :inclusion]}` on `action.status`. The Gateway rejects the message with HTTP 422 and includes `"detail": "invalid value for action.status: timeout"` in the response body.

---

### FR-6.5: Root Node Detection via parent_step_id

The `meta.parent_step_id` field MUST be optional (nil is a valid value). A DecisionLog with `meta.parent_step_id: nil` MUST be treated as a root node in the causal DAG. The Topology Engine (FRD-008) reads this field to construct directed edges; a nil value indicates no incoming edge. The schema MUST NOT add a validation error when `meta.parent_step_id` is nil, and the Gateway MUST NOT reject a message solely because `meta.parent_step_id` is absent.

**Positive path**: A payload omitting `parent_step_id` produces `meta.parent_step_id: nil` in the struct. The Topology Engine treats the resulting node as a DAG root with no parent edge.

**Negative path**: A payload with `"parent_step_id": ""` (empty string) SHOULD be treated as nil via a custom changeset trim step so that an empty string does not masquerade as a valid UUID reference. The trim step MUST convert empty string to nil before the UUID format check.

---

### FR-6.6: Schema Versioning via capability_version

The `identity.capability_version` field MUST carry a semver string (e.g., `"1.2.0"`) identifying the schema version the sending agent is using. The Gateway MUST read this field after successful validation and look up the version in the Capability Map (`Observatory.Gateway.CapabilityMap`). If the version is registered and marked active, the message MUST proceed. If the version is unknown or deprecated, the Gateway MAY still accept the message but MUST emit a warning-level log entry with `agent_id` and `capability_version` so that operators can detect N-1 drift. The schema itself MUST NOT validate semver format beyond confirming the field is a non-empty string; format enforcement is delegated to the Capability Map lookup.

**Positive path**: A message carrying `"capability_version": "2.0.0"` passes schema validation. The Capability Map lookup finds the version active. The message is forwarded without a warning log.

**Negative path**: A message carrying `"capability_version": ""` fails the `validate_required` check on `identity.capability_version`, causing HTTP 422. A message carrying `"capability_version": "0.9.0"` (unregistered) passes schema validation but triggers a warning log. The message is still forwarded.

---

### FR-6.7: entropy_score Gateway Overwrite

The `cognition.entropy_score` field in the incoming payload is agent-reported and MUST be treated as informational only. Before the Gateway broadcasts a validated DecisionLog on any PubSub topic, it MUST overwrite `cognition.entropy_score` with the value computed by `Observatory.Mesh.EntropyComputer.compute/1` (FRD-009). The overwrite MUST occur after validation succeeds and before the PubSub broadcast. Agents MUST NOT rely on their submitted `entropy_score` being preserved in the broadcast message. If the `cognition` section is nil, the overwrite step MUST be skipped entirely.

**Positive path**: An agent submits a DecisionLog with `cognition.entropy_score: 0.2`. The EntropyComputer computes `0.75`. The struct broadcast on PubSub carries `cognition.entropy_score: 0.75`. The original agent-supplied value is discarded.

**Negative path**: If `cognition` is nil, the Gateway skips calling `EntropyComputer.compute/1` and broadcasts the struct with `cognition: nil`. No `FunctionClauseError` or nil dereference occurs.

---

### FR-6.8: JSON Deserialization from HTTP Request

The Gateway endpoint MUST decode the incoming HTTP request body as JSON and cast it into a `DecisionLog` changeset using `Ecto.Changeset.cast/4`. The JSON keys MUST use string form (e.g., `"trace_id"`, `"agent_id"`); the changeset layer handles atom conversion. Nested objects in the JSON body MUST map to their corresponding embedded schema sections. The endpoint MUST reject payloads that are not valid JSON with HTTP 400 before reaching the schema validation step. A valid JSON body that fails schema validation MUST produce HTTP 422, not HTTP 400.

**Positive path**: A well-formed JSON body is decoded by `Plug.Parsers` into a params map. The controller passes the map to `DecisionLog.changeset/2`. The changeset is valid. The controller extracts the struct via `Ecto.Changeset.apply_changes/1` and forwards it.

**Negative path**: A request body containing malformed JSON (e.g., `{trace_id: missing_quotes}`) causes `Plug.Parsers` to return a `Plug.Parsers.ParseError`. The endpoint MUST rescue this error and respond with HTTP 400 `{"status": "error", "reason": "invalid_json"}` before the changeset layer is invoked.

---

### FR-6.9: UI Field Derivations Contract

The schema MUST guarantee that the following field-to-UI derivation contracts are stable across schema versions: `meta.parent_step_id` drives Topology Map directed edges; `cognition.reasoning_chain` (array of strings) drives Reasoning Playback; `cognition.entropy_score` drives Entropy Alert thresholds; `state_delta.cumulative_session_cost` drives the Cost Heatmap; `control.hitl_required` (boolean) drives HITL Gate activation; `control.is_terminal` (boolean) drives terminal node detection in the Topology Map. Any schema change that renames or removes these fields MUST be treated as a breaking change and MUST result in a major version bump in `identity.capability_version` for agents publishing the new format.

**Positive path**: The Topology Map LiveView reads `log.meta.parent_step_id` directly from the broadcast struct. The field is always present (possibly nil) because it is declared in the schema. Pattern matching on the struct is safe.

**Negative path**: A proposed schema refactor that renames `state_delta.cumulative_session_cost` to `state_delta.total_cost` MUST NOT be applied without updating the Cost Heatmap component, incrementing the capability_version major, and documenting the migration in a new ADR. The FRD blocks silent field renames.

---

## Out of Scope (Phase 1)

- Postgres persistence of DecisionLog records as a queryable table
- Multi-tenant namespace isolation on DecisionLog fields
- Binary or MessagePack encoding formats (JSON only in Phase 1)
- Streaming or chunked DecisionLog payloads
- Field-level encryption for `action.tool_input` or other sensitive fields

## Related ADRs

- [ADR-014](../../decisions/ADR-014-decision-log-envelope.md) -- Defines the canonical DecisionLog schema, required fields, optional sections, and UI derivation contracts
- [ADR-017](../../decisions/ADR-017-causal-dag-parent-step-id.md) -- Specifies how `meta.parent_step_id` drives causal DAG edge construction
- [ADR-018](../../decisions/ADR-018-entropy-score-loop-detection.md) -- Specifies Gateway entropy_score overwrite behavior after validation
