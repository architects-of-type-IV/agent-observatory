---
id: UC-0249
title: Broadcast Topology Updates via gateway:topology PubSub Topic
status: draft
parent_fr: FR-8.13
adrs: [ADR-016]
---

# UC-0249: Broadcast Topology Updates via gateway:topology PubSub Topic

## Intent
`TopologyBuilder` is the sole publisher on the `"gateway:topology"` PubSub topic. The Fleet Command LiveView subscribes to this topic at mount time and forwards each received payload to the `TopologyMap` JS hook via `push_event/3`. The Fleet Command LiveView must never read ETS directly — all topology state changes arrive exclusively through `"gateway:topology"` broadcasts.

## Primary Actor
`Observatory.Gateway.TopologyBuilder`

## Supporting Actors
- Fleet Command LiveView (`lib/observatory_web/live/fleet_command_live.ex`)
- Phoenix PubSub (topic `"gateway:topology"`)
- `TopologyMap` JS hook (`assets/js/hooks/topology_map.js`)

## Preconditions
- `TopologyBuilder` is running and has received at least one DAG delta event from `CausalDAG`.
- Fleet Command LiveView is mounted and has subscribed to `"gateway:topology"` inside `mount/3`.
- The `TopologyMap` hook is registered and active on the client canvas element.

## Trigger
`TopologyBuilder` finishes computing updated node and edge lists after processing a DAG delta event.

## Main Success Flow
1. `CausalDAG` broadcasts a delta for session `"sess-abc"`.
2. `TopologyBuilder` receives the delta and calls `CausalDAG.get_session_dag("sess-abc")`.
3. `TopologyBuilder` derives `nodes` and `edges` descriptor lists from the adjacency map.
4. `TopologyBuilder` broadcasts `%{nodes: nodes, edges: edges}` to `"gateway:topology"`.
5. Fleet Command LiveView receives the broadcast in its `handle_info/2` callback.
6. The LiveView calls `push_event(socket, "topology_update", %{nodes: nodes, edges: edges})`.
7. The `TopologyMap` JS hook receives the `"topology_update"` event and triggers a canvas redraw.
8. The canvas displays the updated node and edge state within one animation frame.

## Alternate Flows
### A1: TopologyBuilder restarts after crash
Condition: `TopologyBuilder` crashes and is restarted by its supervisor.
Steps:
1. On first successful DAG delta after restart, `TopologyBuilder` calls `get_session_dag/1` for each active session.
2. It broadcasts a full snapshot to `"gateway:topology"`.
3. Fleet Command LiveView receives the full snapshot and redraws the canvas from the latest known state.

## Failure Flows
### F1: TopologyBuilder crashes between two DAG updates
Condition: `TopologyBuilder` is down for one or more DAG delta intervals.
Steps:
1. Fleet Command LiveView receives no `"gateway:topology"` broadcast during the outage.
2. The canvas retains the last known node and edge state without error.
3. When `TopologyBuilder` restarts, its first broadcast is a full snapshot (see A1).
Result: No crash in the LiveView; canvas shows stale-but-valid state during the outage.

## Gherkin Scenarios

### S1: Topology update propagates from TopologyBuilder to canvas
```gherkin
Scenario: Agent state change reaches canvas via gateway:topology broadcast
  Given Fleet Command LiveView is mounted and subscribed to "gateway:topology"
  And the TopologyMap hook is active on the canvas element
  When TopologyBuilder broadcasts a topology update with an agent in state "active"
  Then Fleet Command LiveView receives the broadcast and calls push_event with "topology_update"
  And the TopologyMap hook redraws the canvas with the agent node in the active color
```

### S2: Fleet Command LiveView does not read ETS directly
```gherkin
Scenario: Fleet Command LiveView has no direct ETS read calls for topology data
  Given Fleet Command LiveView is mounted
  When the LiveView module source is inspected
  Then no call to :ets.lookup or CausalDAG.get_session_dag is present in the LiveView module
  And all topology state arrives via handle_info receiving from "gateway:topology"
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/live/fleet_command_live_test.exs` passes a test that broadcasts a `"gateway:topology"` message to a mounted Fleet Command LiveView and asserts `push_event/3` is called with event name `"topology_update"` and a map containing `nodes` and `edges` keys.
- [ ] `mix test test/observatory/gateway/topology_builder_test.exs` passes a test that verifies `TopologyBuilder` broadcasts only to `"gateway:topology"` and that the Fleet Command LiveView module contains no direct calls to `CausalDAG.get_session_dag/1` or `:ets.lookup`.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** DAG delta event from `CausalDAG`; session adjacency map from `CausalDAG.get_session_dag/1`.
**Outputs:** `%{nodes: [...], edges: [...]}` broadcast on `"gateway:topology"`; `push_event/3` call on the LiveView socket.
**State changes:** Fleet Command LiveView socket assigns updated with latest topology; `TopologyMap` hook canvas redrawn.

## Traceability
- Parent FR: FR-8.13
- ADR: [ADR-016](../../decisions/ADR-016-canvas-topology-renderer.md)
