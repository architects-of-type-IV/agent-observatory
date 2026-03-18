# ichor_memory_core

ETS-backed agent memory store with disk persistence. Provides structured memory blocks,
recall history, and archival search for all agents in the fleet.

## Ash Domains

None. This app uses raw ETS tables, not Ash resources.

## Key Modules

| Module | Responsibility |
|---|---|
| `Ichor.MemoryStore.Tables` | ETS table definitions, capacities, and data directory config |
| `Ichor.MemoryStore.Blocks` | CRUD for named memory blocks (label, value, limit, read_only) |
| `Ichor.MemoryStore.Recall` | Per-agent recall history (recent conversation entries) |
| `Ichor.MemoryStore.Archival` | Per-agent archival search (long-term JSONL-backed storage) |
| `Ichor.MemoryStore.Persistence` | Load-from-disk and flush-dirty-to-disk for blocks and agents |
| `Ichor.MemoryStore.Broadcast` | PubSub notifications when memory state changes |

## Storage Model

- **Blocks**: shared, labelled key-value entries with per-block size limits
- **Recall**: per-agent ring buffer of recent conversation turns (ETS + JSONL on disk)
- **Archival**: per-agent append-only JSONL store, ETS-cached up to a configured limit

## Dependencies

- `jason` -- JSON encoding for disk persistence
- `ichor_signals` -- PubSub broadcast on memory changes

## Architecture Role

`ichor_memory_core` is consumed by the `Ichor.AgentTools.Memory` and `Ichor.AgentTools.Recall`
MCP tool modules in `ichor`. Agents read and write memory via MCP tool calls which
delegate to this library. No Ash, no Ecto -- pure ETS + file I/O at the boundary.
