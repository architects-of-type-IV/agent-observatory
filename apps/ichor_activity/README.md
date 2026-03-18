# ichor_activity

Ash Domain for in-memory agent activity views: messages, tasks, and errors.

## Ash Domains

**`Ichor.Activity`** -- owns three resources backed by `Ash.DataLayer.Simple` (no database table).
Data is populated at read time by custom preparations that pull from the in-memory event store.

| Resource | Description |
|---|---|
| `Ichor.Activity.Message` | Inter-agent messages derived from SendMessage hook events |
| `Ichor.Activity.Task` | Task status snapshots loaded from the runtime |
| `Ichor.Activity.Error` | Agent error records surfaced from event history |

## Key Modules

| Module | Responsibility |
|---|---|
| `Ichor.Activity` | Ash Domain entry point |
| `Ichor.Activity.Preparations.LoadMessages` | Fetches recent inter-agent messages at read time |
| `Ichor.Activity.Preparations.LoadTasks` | Fetches task state snapshots at read time |
| `Ichor.Activity.Preparations.LoadErrors` | Fetches agent error records at read time |

## Dependencies

- `ash` -- Ash framework only; no database dependency
- No sibling app dependencies

## Architecture Role

`ichor_activity` provides a queryable Ash facade over ephemeral runtime data.
No records are written to SQLite. The Simple data layer allows LiveView to query
activity using standard Ash action patterns without coupling to a persistence layer.
