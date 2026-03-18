# ichor_dag

Ash Domain for DAG execution: the control plane for parallel agent work through directed
acyclic graphs of claimable jobs with dependency chains.

## Ash Domains

**`Ichor.Dag`** -- owns two persisted resources backed by SQLite via `AshSqlite`.

| Resource | Description |
|---|---|
| `Ichor.Dag.Run` | A single DAG execution run, linked to a Genesis node |
| `Ichor.Dag.Job` | A claimable execution unit within a run (status: pending -> in_progress -> completed/failed) |

## Key Modules

| Module | Responsibility |
|---|---|
| `Ichor.Dag` | Ash Domain entry point |
| `Ichor.Dag.Job` | Claimable job resource with `claim`, `complete`, `fail`, `reset`, `reassign` actions |
| `Ichor.Dag.Run` | DAG run resource with wave-based topological ordering |
| `Ichor.Dag.Job.Preparations.FilterAvailable` | Filters jobs by unblocked dependency chains |
| `Ichor.Dag.RuntimeCallbacks` | After-action hooks that emit signals on job state transitions |
| `Ichor.Dag.Handoff` | Handoff protocol between DAG runs and genesis nodes |

## Dependencies

- `ichor_data` -- shared `Ichor.Repo` (SQLite)
- `ichor_genesis` -- Job records reference Genesis subtask IDs
- `ash`, `ash_sqlite`

## Architecture Role

`ichor_dag` is the execution control plane. Genesis (planning) produces the spec;
`ichor_dag` turns it into a live, claimable job queue. Agents claim jobs via the
`Ichor.Dag.Job.claim/1` code interface. The runtime orchestration (spawning workers,
supervising runs) lives in `ichor` (the main app).
