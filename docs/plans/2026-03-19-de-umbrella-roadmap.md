# De-Umbrella Roadmap

## Intent

The current umbrella is a stabilization scaffold. It is not the intended permanent
packaging model.

The target end state is a single primary app, `ichor`, with clear internal namespace
boundaries and no hidden second monolith spread across sibling apps.

The umbrella remains in place until:

- host-app leakage into sibling apps is removed
- domain and runtime boundaries are semantically stable
- merge-back reduces complexity instead of reintroducing ambiguity

## Target Host Structure

Future structure inside `apps/ichor/lib/ichor`:

- `signals/`
- `data/`
- `workshop/`
- `genesis/`
- `tasks/`
- `dag/`
- `mes/`
- `fleet/`
- `archon/`
- `gateway/`
- `monitoring/` only if shared observers remain distinct

`apps/ichor/lib/ichor_web` remains the Phoenix UI layer.

## Semantic Boundaries

- `Ichor.Signals`: system nervous system; universal publish/subscribe fabric
- `Ichor.Archon`: managerial layer over all signals
- `Ichor.Workshop`: canonical source of agent, team, and comm-rule definitions
- `Ichor.Fleet`: runtime execution, routing, lifecycle, and oversight
- `Ichor.Tasks`: canonical task model and storage
- `Ichor.Dag`: Elixir runtime form of the DAG skill over `Ichor.Tasks`
- `Ichor.Genesis`: planning and SDLC artifacts
- `Ichor.Mes`: factory/facility operation over runs
- `Ichor.Gateway`: ingress, delivery, topology, HITL, and runtime transport glue

## Merge-Back Order

Merge only after readiness gates pass.

Merge back in this order:

1. `ichor_events`
2. `ichor_activity`
3. `ichor_memory_core`
4. `ichor_mesh`
5. `ichor_genesis`
6. `ichor_mes`
7. `ichor_fleet`
8. `ichor_workshop`
9. `ichor_dag`

Keep these separate the longest:

- `ichor_signals`
- `ichor_data`
- `ichor_tmux_runtime`

## Readiness Gates

An app is merge-back ready only if:

- host code uses app/domain interfaces instead of direct `Ash.*` calls
- host code does not call resource modules directly unless the resource itself is the public domain API
- no special xref exclusions or dependency hacks are required
- no duplicate runtime logic exists in both host and sibling app
- `mix precommit` passes
- `mix xref graph --format cycles --label compile-connected` reports no cycles
- docs match the actual code boundaries

## Immediate Work

1. Keep removing host-level direct resource usage.
2. Finish DAG terminology cleanup (`swarm_*` -> `dag_*` and `swarm_state` -> `dag_state`).
3. Slice `apps/ichor` by page/runtime feature:
   - pipeline
   - fleet
   - workshop
   - signals
   - mes
4. Keep `README.md` and `REFACTOR.md` files aligned with the real code before every merge-back step.
5. Use the boundary audit task as the first gate before any move.
