# Merge-Back Gates

## How To Use

Before merging any umbrella app back into `apps/ichor`:

1. Read the app `README.md`
2. Read the app `REFACTOR.md`
3. Run `mix boundary.audit`
4. Run `mix precommit`
5. Run `MIX_BUILD_PATH=_build_xref mix xref graph --format cycles --label compile-connected`

Only proceed if the code matches the documented boundary and the target app passes the gates below.

## Gate Checklist

### Boundary Gate

- No direct `Ash.create`, `Ash.update`, `Ash.destroy`, `Ash.read`, or `Ash.get` calls from `apps/ichor/lib`
- No direct resource-level calls from host code when the owning domain should be the public boundary
- No duplicate host runtime logic remains alongside the sibling app logic

### Terminology Gate

- No stale `swarm_*` terminology remains for DAG pipeline concepts
- Public UI and runtime terms match the semantic model:
  - planning = Genesis
  - tasks = Tasks
  - pipeline runtime = DAG
  - team definition = Workshop
  - execution/runtime = Fleet
  - factory operation = MES

### Structural Gate

- No compile-connected cycles
- No xref workarounds or dependency hacks needed for the target boundary
- No hidden alternate implementation remains in the old sibling app after the move

### Documentation Gate

- `README.md` describes the actual role of the app
- `REFACTOR.md` reflects current code, not historical assumptions
- Future target namespace inside `apps/ichor/lib/ichor` is identified before the move

### Validation Gate

- `mix precommit` passes
- Page-level smoke coverage remains green for:
  - pipeline
  - fleet
  - workshop
  - signals
  - mes

## Current Merge-Back Status

### Not Ready

- `ichor_workshop`
  because Workshop is not yet the sole source of team formation
- `ichor_dag`
  because persisted DAG records and DAG runtime skill behavior are still split intentionally
- `ichor_signals`
  keep separate longest
- `ichor_data`
  keep separate longest
- `ichor_tmux_runtime`
  keep separate longest

### Candidate Soonest

- `ichor_events`
- `ichor_activity`

These are the simplest to merge once the host app stops bypassing their boundaries.
