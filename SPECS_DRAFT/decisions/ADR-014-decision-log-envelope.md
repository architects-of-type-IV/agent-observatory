---
id: ADR-014
title: DecisionLog Universal Message Envelope
date: 2026-02-21
status: proposed
related_tasks: []
parent: ADR-013
superseded_by: null
---
# ADR-014 DecisionLog Universal Message Envelope
[2026-02-21] proposed

## Related ADRs
- [ADR-013](ADR-013-hypervisor-platform-scope.md) Hypervisor Platform Scope (parent)
- [ADR-015](ADR-015-gateway-schema-interceptor.md) Gateway Schema Interceptor
- [ADR-017](ADR-017-causal-dag-parent-step-id.md) Causal DAG via parent_step_id
- [ADR-018](ADR-018-entropy-score-loop-detection.md) Entropy Score as Loop Detection Primitive

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Project Brief §4.2 | [PROJECT-BRIEF.md](../PROJECT-BRIEF.md) | DecisionLog schema definition and UI derivation table |

## Context

The entire Hypervisor UI — topology map edges, reasoning playback, entropy alerts, cost heatmaps, state scrubbing — derives from structured fields on agent messages. If these fields are not standardized, each UI feature must negotiate with arbitrary message shapes per agent type. At mesh scale this is unmanageable.

The question is: what is the minimal, sufficient schema that enables all planned UI features, and how should it be versioned?

## Options Considered

1. **Free-form JSON with UI-level extraction** — Agents emit whatever they want; UI tries to find useful fields by convention or pattern matching.
   - Con: Each new agent version breaks UI assumptions. No contract to enforce. Forensic Inspector cannot provide consistent queries across agent types.

2. **Typed Ecto schema enforced at ingest** — The Gateway defines an Ecto changeset for DecisionLog. Messages that don't conform are rejected at the boundary.
   - Pro: Compile-time type safety, validation reuse across tests, Ash resource integration possible.
   - Con: Schema evolution (adding fields) requires changeset updates; but this is manageable with `cast/3` optional fields.

3. **JSON Schema + external validator** — Use a JSON Schema document as the contract; validate with a library like `ex_json_schema`.
   - Pro: Language-agnostic; non-Elixir agents can validate before sending.
   - Con: Runtime-only validation; no Elixir type integration.

## Decision

**Option 2** — Typed Ecto embedded schema for DecisionLog, enforced at the Gateway Schema Interceptor.

The schema has six top-level sections, each as an embedded schema:

```elixir
# lib/observatory/mesh/decision_log.ex
embedded_schema do
  embeds_one :meta, Meta do
    field :trace_id, :string           # UUID v4
    field :parent_step_id, :string     # UUID of previous step (nil = root)
    field :timestamp, :utc_datetime
    field :cluster_id, :string
  end

  embeds_one :identity, Identity do
    field :agent_id, :string
    field :agent_type, :string
    field :capability_version, :string
  end

  embeds_one :cognition, Cognition do
    field :intent, :string
    field :reasoning_chain, {:array, :string}
    field :confidence_score, :float      # 0.0–1.0
    field :strategy_used, :string        # "ReAct", "CoT", "Plan-Execute", etc.
    field :entropy_score, :float         # 0.0–1.0; 0=deterministic, 1=maximally uncertain
  end

  embeds_one :action, Action do
    field :tool_call, :string
    field :tool_input, :string           # JSON-encoded string
    field :tool_output_summary, :string
    field :status, Ecto.Enum, values: [:success, :failure, :pending, :skipped]
  end

  embeds_one :state_delta, StateDelta do
    field :added_to_memory, {:array, :string}
    field :tokens_consumed, :integer
    field :cumulative_session_cost, :float
  end

  embeds_one :control, Control do
    field :hitl_required, :boolean, default: false
    field :interrupt_signal, :string     # nil = no interrupt; "pause", "rewrite", "inject"
    field :is_terminal, :boolean, default: false
  end
end
```

**Required fields:** `meta.trace_id`, `meta.timestamp`, `identity.agent_id`, `identity.agent_type`, `identity.capability_version`, `cognition.intent`, `action.status`

**Optional fields:** All others. Agents that don't compute `entropy_score` may omit it; the Gateway defaults to `nil` and skips entropy alerting for that message.

**Schema versioning:** The `identity.capability_version` field (semver) allows the Gateway to apply N-1 schema compatibility. A version registry maps capability_version → accepted field set.

## Rationale

Ecto embedded schemas give us:
1. Compile-time type checking for all Gateway code that constructs or pattern-matches DecisionLog
2. Changeset-based validation reuse in tests
3. Clean `cast_embed/3` for optional sections — an agent that omits `cognition` produces a valid log with `nil` cognition rather than a validation error

The schema is intentionally narrow: it captures what is needed for the six UI features listed in §4.2 of the brief, nothing more. Fields are added when a UI feature requires them, not speculatively.

## Consequences

- New module: `lib/observatory/mesh/decision_log.ex` (embedded schema + changeset)
- Gateway Schema Interceptor (ADR-015) validates against this changeset
- UI feature derivations (topology edges, entropy alerts, cost heatmap) read from typed struct fields
- Agents must emit JSON matching this schema; SDK helpers may be provided
- Schema changes require bumping `capability_version` in the agent and updating the Gateway version registry
