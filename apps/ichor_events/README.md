# ichor_events

Ash Domain for Claude hook event ingestion and session tracking.

## Ash Domains

**`Ichor.Events`** -- owns two persisted resources backed by SQLite via `AshSqlite`.

| Resource | Description |
|---|---|
| `Ichor.Events.Event` | A single Claude hook event (PreToolUse, PostToolUse, SessionStart, etc.) |
| `Ichor.Events.Session` | An agent session grouping related events by `session_id` |

## Key Modules

| Module | Responsibility |
|---|---|
| `Ichor.Events` | Ash Domain entry point |
| `Ichor.Events.Event` | Persists hook payloads with `hook_event_type`, `session_id`, `source_app`, tool metadata |
| `Ichor.Events.Session` | Session-level aggregation over events |

## Event Types

`hook_event_type` is constrained to the Claude hook event vocabulary:
`SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`,
`PostToolUseFailure`, `PermissionRequest`, `Notification`, `SubagentStart`,
`SubagentStop`, `Stop`, `PreCompact`, `TaskCompleted`.

## Dependencies

- `ichor_data` -- shared `Ichor.Repo` (SQLite)
- `ash`, `ash_sqlite`

## Architecture Role

`ichor_events` is the raw event journal. Every Claude hook event arriving at the gateway
is written here. The main `ichor` app's `Ichor.Gateway` layer ingests events from
external agents and writes them to this domain. Analytics, feed views, and the
session drilldown LiveView all read from this domain.
