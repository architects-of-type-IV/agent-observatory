# ichor_mes

Ash Domain for the Manufacturing Execution System (MES): the continuous manufacturing
nervous system that autonomously spawns agent teams to research and build new ICHOR subsystems.

## Ash Domains

**`Ichor.Mes`** -- owns one persisted resource backed by SQLite via `AshSqlite`.

| Resource | Description |
|---|---|
| `Ichor.Mes.Project` | A MES project record tracking a subsystem from proposal through completion |

## Project Lifecycle

```
proposed -> active -> genesis (planning) -> building -> complete
```

Completed projects are hot-loaded into the running BEAM as standalone Mix projects.

## Key Modules

| Module | Responsibility |
|---|---|
| `Ichor.Mes` | Ash Domain entry point |
| `Ichor.Mes.Project` | Project resource with status transitions, research context, and genesis linkage |

## Dependencies

- `ichor_data` -- shared `Ichor.Repo` (SQLite)
- `ash`, `ash_sqlite`

## Architecture Role

`ichor_mes` defines the data model for MES projects. The runtime orchestration
(scheduler, team spawner, research ingestor, subsystem loader) lives in the main `ichor`
app under `Ichor.Mes.*`. `ichor_genesis` depends on `ichor_mes` because Genesis nodes
originate from MES projects.
