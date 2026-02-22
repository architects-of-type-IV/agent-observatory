---
id: UC-0216
title: Update Topology Node to :schema_violation State on Violation Event
status: draft
parent_fr: FR-7.8
adrs: [ADR-015]
---

# UC-0216: Update Topology Node to :schema_violation State on Violation Event

## Intent
This use case covers how the Topology Map LiveView handles a `SchemaViolationEvent` received from `"gateway:violations"`. The LiveView must update the node for the offending `agent_id` to the `:schema_violation` state, render it with an orange highlight, and clear the state after a configurable timeout (default 30 seconds) or upon receipt of the next valid message from the same agent. If the `agent_id` has no corresponding node (agent never sent a valid message), a ghost node must be created rather than dropping the event.

## Primary Actor
Topology Map LiveView

## Supporting Actors
- `"gateway:violations"` (PubSub topic, source of violation events)
- `"gateway:messages"` (PubSub topic, source of valid messages that clear violation state)
- Node state machine (atoms: `:active`, `:idle`, `:error`, `:offline`, `:schema_violation`)
- Canvas renderer (renders orange highlight for `:schema_violation` state)
- `Process.send_after/3` (schedules state clearance after 30 seconds)

## Preconditions
- The Topology Map LiveView is subscribed to both `"gateway:violations"` and `"gateway:messages"`.
- The node state machine recognizes `:schema_violation` as a valid state alongside `:active`, `:idle`, `:error`, and `:offline`.
- The Canvas renderer has an orange highlight rule for `:schema_violation` nodes.
- A timeout value (default 30 seconds) is configurable for state clearance.

## Trigger
The Topology Map LiveView receives `{:schema_violation, event}` in its `handle_info/2` callback.

## Main Success Flow
1. The LiveView `handle_info/2` receives `{:schema_violation, event}` from `"gateway:violations"`.
2. The LiveView extracts `event["agent_id"]` (e.g., `"agent-42"`).
3. The LiveView finds the node for `"agent-42"` in its assigns.
4. The LiveView updates the node state to `:schema_violation`.
5. The LiveView stores the node's previous state so it can be restored after the timeout.
6. The Canvas renderer applies an orange highlight to the `"agent-42"` node.
7. The LiveView schedules a `Process.send_after(self(), {:clear_schema_violation, "agent-42"}, 30_000)`.
8. After 30 seconds, `handle_info/2` receives `{:clear_schema_violation, "agent-42"}`.
9. The LiveView returns the node to its previous state (e.g., `:idle`).
10. The Canvas renderer removes the orange highlight.
11. No page refresh is required at any point.

## Alternate Flows
### A1: Valid message received before timeout clears violation state early
Condition: The LiveView receives `{:decision_log, log}` from `"gateway:messages"` for `"agent-42"` before the 30-second timer fires.
Steps:
1. The LiveView receives `{:decision_log, log}` with `log.identity.agent_id == "agent-42"`.
2. The LiveView cancels the pending `{:clear_schema_violation, "agent-42"}` timer.
3. The LiveView transitions the node back to `:active` (or appropriate state based on the message).
4. The Canvas renderer updates the node color immediately.

## Failure Flows
### F1: agent_id has no known node (ghost node creation)
Condition: `event["agent_id"]` does not correspond to any existing node in the Topology Map.
Steps:
1. The LiveView finds no matching node for `event["agent_id"]`.
2. The LiveView creates a new ghost node with `agent_id` as the label and state `:schema_violation`.
3. The ghost node is rendered with an orange highlight.
4. The ghost node state clears after the default 30-second timeout.
5. The event is not dropped.
Result: Violations from previously unseen agents are visible in the Topology Map.

## Gherkin Scenarios

### S1: Known node transitions to schema_violation and is highlighted orange
```gherkin
Scenario: Topology node for known agent transitions to :schema_violation state on violation event
  Given the Topology Map has an existing node for agent_id "agent-42" in :idle state
  And the LiveView is subscribed to "gateway:violations"
  When the LiveView handle_info/2 receives {:schema_violation, event} with agent_id "agent-42"
  Then the node state for "agent-42" is updated to :schema_violation
  And the Canvas renderer applies an orange highlight to the "agent-42" node
  And after 30 seconds the node state is restored to :idle
```

### S2: Violation state clears when next valid message arrives before timeout
```gherkin
Scenario: next valid message from same agent clears schema_violation state before timeout
  Given the Topology Map has node "agent-42" in :schema_violation state with an active clearance timer
  When the LiveView receives {:decision_log, log} from "gateway:messages" for agent_id "agent-42"
  Then the node state for "agent-42" is immediately transitioned away from :schema_violation
  And the clearance timer is cancelled
  And the orange highlight is removed from the node
```

### S3: Unknown agent_id creates a ghost node rather than dropping the event
```gherkin
Scenario: schema_violation event for unknown agent creates a ghost node in the Topology Map
  Given the Topology Map has no node for agent_id "new-agent-99"
  When the LiveView receives {:schema_violation, event} with agent_id "new-agent-99"
  Then a ghost node is created for "new-agent-99" with state :schema_violation
  And the ghost node is rendered with an orange highlight
  And the event is not silently discarded
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that subscribes a test LiveView to `"gateway:violations"`, broadcasts a `SchemaViolationEvent`, and asserts the LiveView assigns contain a node with `state: :schema_violation` for the offending `agent_id`.
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that advances the timer by 30 seconds and asserts the node state is no longer `:schema_violation`.
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that sends a `SchemaViolationEvent` for an unknown `agent_id` and asserts a ghost node with `state: :schema_violation` is created rather than the event being dropped.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** `{:schema_violation, event}` where `event["agent_id"]` identifies the offending node; 30-second timeout configuration.
**Outputs:** Node state update to `:schema_violation`; orange highlight in Canvas renderer; timer scheduled for state clearance.
**State changes:** LiveView assigns are updated with the new node state. Timer state is added. No ETS or database state is modified.

## Traceability
- Parent FR: FR-7.8
- ADR: [ADR-015](../../decisions/ADR-015-gateway-schema-interceptor.md)
