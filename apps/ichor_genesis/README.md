# ichor_genesis

Ash Domain for the Genesis planning pipeline: turns MES subsystem proposals into
fully planned, DAG-ready executable projects.

## Ash Domains

**`Ichor.Genesis`** -- owns ten persisted resources backed by SQLite via `AshSqlite`.

| Resource | Description |
|---|---|
| `Ichor.Genesis.Node` | Root planning node; entry point for a Genesis run |
| `Ichor.Genesis.Adr` | Architecture Decision Record produced in Mode A |
| `Ichor.Genesis.Feature` | Feature / FRD produced in Mode B |
| `Ichor.Genesis.UseCase` | Use case produced in Mode B |
| `Ichor.Genesis.Checkpoint` | Gate check result at a pipeline stage |
| `Ichor.Genesis.Conversation` | Archived LLM conversation turn |
| `Ichor.Genesis.Phase` | Implementation phase in the Mode C roadmap |
| `Ichor.Genesis.Section` | Section within a phase |
| `Ichor.Genesis.Task` | Task within a section |
| `Ichor.Genesis.Subtask` | Subtask within a task; maps 1:1 to a `Ichor.Dag.Job` |

## Pipeline Stages

```
MES brief (proposed)
  -> Mode A: ADR generation
  -> Mode B: FRDs + Use Cases
  -> Mode C: roadmap phasing + DAG export
  -> Ichor.Dag execution
```

## Dependencies

- `ichor_data` -- shared `Ichor.Repo` (SQLite)
- `ichor_mes` -- Genesis nodes originate from MES projects
- `ash`, `ash_sqlite`

## Architecture Role

`ichor_genesis` is the planning domain. It mirrors the external Genesis app schema
for future sync but operates standalone in ICHOR's SQLite. The `ichor` main app
drives the pipeline via `Ichor.Genesis.ModeRunner` and `Ichor.Genesis.ModeSpawner`.
When a Genesis node reaches DAG-ready state, `Ichor.Dag` takes over execution.
