# ichor_mesh

In-memory causal DAG and message envelope schemas for the ICHOR agent observation layer.

## Ash Domains

None. This app uses Ecto embedded schemas and ETS, not Ash resources or a database table.

## Key Modules

| Module | Responsibility |
|---|---|
| `Ichor.Mesh.CausalDAG` | ETS-backed GenServer maintaining one adjacency table per active session. Handles out-of-order arrival via a 30-second orphan buffer, enforces acyclicity, and broadcasts incremental deltas over PubSub |
| `Ichor.Mesh.DecisionLog` | Ecto embedded schema for the universal agent message envelope (meta, identity, cognition, action, state_delta, control sections) |

## DecisionLog Structure

Every agent that speaks to the gateway sends a `DecisionLog`. It is validated in-memory
via Ecto changesets and never persisted directly -- it is forwarded over PubSub and
indexed into the CausalDAG.

## Dependencies

- `ecto` -- Embedded schema validation only (no database)
- `ichor_signals` -- PubSub broadcast for DAG delta events

## Architecture Role

`ichor_mesh` is the observation backbone. The gateway (`ichor`) validates incoming
HTTP payloads as `DecisionLog` structs and inserts them into `CausalDAG`. The
session drilldown LiveView subscribes to `session:dag:<session_id>` to render
live causal trees of agent decisions.
