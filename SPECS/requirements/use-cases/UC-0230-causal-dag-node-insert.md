---
id: UC-0230
title: Insert a Valid Node into the Causal DAG
status: draft
parent_fr: FR-8.1
adrs: [ADR-017]
---

# UC-0230: Insert a Valid Node into the Causal DAG

## Intent
When a DecisionLog message arrives at the Gateway, `CausalDAG.insert/2` must write a fully-populated Node struct to the session's ETS table or reject it with a structured error if any required field is absent. This UC covers both the successful write path and the missing-fields guard, ensuring callers always receive a deterministic outcome.

## Primary Actor
CausalDAG

## Supporting Actors
- ETS table keyed by `{session_id, trace_id}`
- SchemaInterceptor (upstream caller)

## Preconditions
- `Observatory.Mesh.CausalDAG` GenServer is running.
- An ETS table for `session_id` exists or can be created on demand.

## Trigger
`CausalDAG.insert/2` is called with a `session_id` string and a Node struct.

## Main Success Flow
1. Caller supplies a Node struct containing all nine required fields: `trace_id`, `parent_step_id`, `agent_id`, `intent`, `confidence_score`, `entropy_score`, `action_status`, `timestamp`, and `children`.
2. `CausalDAG` validates that every required field is present and non-nil (except `parent_step_id`, which may be nil for root nodes).
3. `CausalDAG` writes the node to the ETS table under the composite key `{session_id, trace_id}`.
4. `CausalDAG` returns `:ok` to the caller.

## Alternate Flows
### A1: Session ETS table does not yet exist
Condition: First node is being inserted for a brand-new session_id.
Steps:
1. `CausalDAG` creates a new ETS table for that session_id before writing.
2. Node is inserted normally; `:ok` is returned.

## Failure Flows
### F1: Required field missing from Node struct
Condition: The supplied Node struct omits one or more of the nine required fields.
Steps:
1. `CausalDAG` detects the missing field during pre-insert validation.
2. `CausalDAG` writes nothing to ETS.
3. `CausalDAG` returns `{:error, :missing_fields}` to the caller.
Result: ETS table is unchanged; no delta broadcast is emitted.

## Gherkin Scenarios

### S1: All required fields present — node written to ETS
```gherkin
Scenario: Valid Node struct is inserted into CausalDAG
  Given an ETS table exists for session_id "sess-abc"
  And a Node struct is prepared with all nine required fields populated
  When CausalDAG.insert/2 is called with "sess-abc" and the Node struct
  Then the node is stored in ETS under key {"sess-abc", trace_id}
  And CausalDAG.insert/2 returns :ok
```

### S2: Missing field — insert rejected
```gherkin
Scenario: Node struct missing agent_id is rejected
  Given an ETS table exists for session_id "sess-abc"
  And a Node struct is prepared with the agent_id field omitted
  When CausalDAG.insert/2 is called with "sess-abc" and the incomplete Node struct
  Then no entry is written to the ETS table
  And CausalDAG.insert/2 returns {:error, :missing_fields}
```

## Acceptance Criteria
- [ ] `mix test test/observatory/mesh/causal_dag_test.exs` passes a test that calls `CausalDAG.insert/2` with a fully-populated Node struct and asserts `:ok` is returned and the node is retrievable via `CausalDAG.get_session_dag/1`.
- [ ] `mix test test/observatory/mesh/causal_dag_test.exs` passes a test that calls `CausalDAG.insert/2` with a Node struct missing one required field and asserts `{:error, :missing_fields}` is returned and the ETS table is unchanged.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `session_id` (string), `Node` struct with fields `trace_id`, `parent_step_id`, `agent_id`, `intent`, `confidence_score`, `entropy_score`, `action_status`, `timestamp`, `children`.
**Outputs:** `:ok` or `{:error, :missing_fields}`.
**State changes:** On success, ETS entry `{session_id, trace_id} => %Node{}` is created.

## Traceability
- Parent FR: FR-8.1
- ADR: [ADR-017](../../decisions/ADR-017-causal-dag-parent-step-id.md)
