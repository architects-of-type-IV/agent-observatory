# Memory Strategy
Related: [Index](INDEX.md) | [Signals Domain](signals-domain.md) | [Supervision Tree](supervision-tree.md)

Covers: ETS tables, per-store specifications, Enum vs Stream decision rules, known risks.

---

## ETS Table Inventory

| Table | Owner Process | Purpose | Key | Value |
|-------|--------------|---------|-----|-------|
| `ichor_events` | `Events.Runtime` | Ring buffer of recent hook events | `{session_id, seq}` | `%Event{}` struct |
| `ichor_sessions` | `Events.Runtime` | Session liveness -- last-seen timestamps | `session_id` | `%{last_seen: DateTime, status: atom}` |
| `ichor_message_log` | `Transport.MessageBus` | Delivery log for directed messages | `message_id` | `%{delivered_at: DateTime, target: String, delivered: integer}` |
| `ichor_signal_buffer` | `Events.Runtime` (after merge) | Signal ring buffer for Dashboard replay | `seq` (`:atomics`) | `%Signal{}` struct |
| `ichor_notes` | `Ichor.Notes` | Human-annotated event notes | `event_id` | `%{note: String, inserted_at: DateTime}` |

Access pattern for all tables: **write through GenServer, read directly from ETS**. This gives serialized writes without serializing reads.

---

## Per-Store Specifications

### Events.Runtime (Event Store)

**Authority**: AD-5 -- canonical source for session liveness and raw hook event history.

**ETS type**: `:ordered_set` on `{session_id, seq}` for events. `:set` for session map.

**Concurrency**: Multiple readers (LiveViews, AgentWatchdog, EventBridge) read concurrently. Single writer (GenServer) ensures monotonic sequence numbers.

**Retention**: Ring buffer with configurable max size (default: 1000 events). Eviction: drop oldest when full.

**After AD-5 fix**: EventStream will NOT auto-create fleet entities. It emits `:session_discovered` signal. Fleet.Runtime subscriber reacts by spawning AgentProcess.

**Streams vs. Enum**: Use `Stream.resource/3` for large event history scans (>1000 events). Use `Enum.filter/2` for live-session queries (bounded: typically <50 sessions).

---

### Transport.MessageBus (Message Delivery Log)

**Authority**: AD-5 -- canonical delivery record for directed agent-to-agent messages.

**ETS type**: `:set` keyed by `message_id`.

**Retention**: Unbounded (messages are small). Prune via periodic Oban worker if growth is a concern.

**Concurrency**: Bus is the sole writer. Dashboard LiveView reads for display.

---

### Memory.Store (Three-Tier Agent Memory)

**Authority**: Letta-compatible in-memory store for agent reasoning context.

**Structure**:
- `core_memory`: Small string blocks (persona, human description). Always in context.
- `archival_memory`: Append-only long-term storage. Searched by embedding.
- `recall_memory`: Conversation history. Queried by recency.

**Persistence**: `Memory.Persistence` flushes to disk on write. `Memory.Storage` handles ETS operations.

**No ETS sharing**: Each agent's memory is owned by that agent's interaction. No cross-agent reads at the ETS level -- queries go through `Memory.Store` GenServer.

---

### Notes (Event Annotations)

**Authority**: Human-authored notes on events. Ephemeral between restarts (not persisted).

**ETS type**: `:set` keyed by `event_id`.

**Owner**: `Ichor.Notes` GenServer. Reads are direct ETS. Writes go through GenServer.

---

## Enum vs. Stream Decision Rules

### Use `Enum` when:

- The collection is **bounded and small** (< a few hundred items): active sessions list, team members, current run tasks.
- You need a **materialized result** immediately: building a map, sorting, deduplicating.
- The collection lives **entirely in memory** already (ETS reads return lists).
- You need **multiple passes**: sort then filter then group.

```elixir
# Correct: active sessions are bounded
active_sessions = Enum.filter(sessions, & &1.status == :active)
sorted = Enum.sort_by(active_sessions, & &1.last_seen, {:desc, DateTime})
```

### Use `Stream` when:

- Processing **large event history** that might not fit comfortably in memory.
- Building a **pipeline with early termination**: `Stream.take_while/2`, `Stream.take/2`.
- Reading from **external sources**: file lines, database cursor, ETS continuation.
- The consumer only needs a **subset** of the data.

```elixir
# Correct: event history could be large
events_stream =
  Stream.resource(
    fn -> :ets.first(:ichor_events) end,
    fn
      :"$end_of_table" -> {:halt, nil}
      key -> {[:ets.lookup(:ichor_events, key)], :ets.next(:ichor_events, key)}
    end,
    fn _ -> :ok end
  )

result = events_stream |> Stream.filter(&match_session/1) |> Enum.take(100)
```

### Never use Stream when:

- You need `length/1` or `count/1` -- these force evaluation anyway.
- The collection is already small -- Stream overhead exceeds benefit.
- You need random access or sorting -- requires materializing the stream.

---

## Memory Risks

### Risk 1: ETS table orphaning

**Scenario**: `Events.Runtime` GenServer crashes before the supervisor restarts it. ETS tables owned by the process are destroyed.

**Mitigation**: Create ETS tables with `:named_table` and ownership transferred to the supervisor via `:heir` option, or use persistent term for the table reference. Alternatively, accept the loss -- events are ephemeral, and the ring buffer will refill.

**Current status**: Not implemented. Acceptable risk for a developer tool (restart is fast).

---

### Risk 2: Message log unbounded growth

**Scenario**: Long-running sessions produce thousands of directed messages. The ETS log grows indefinitely.

**Mitigation**: Add a periodic Oban worker that trims entries older than N hours. Low priority -- messages are small structs.

**Current status**: Not implemented. Monitor in production-like sessions.

---

### Risk 3: Memory.Store large archival under concurrent load

**Scenario**: Multiple agents writing archival memory simultaneously. GenServer becomes a bottleneck.

**Mitigation**: Archival writes are infrequent (only when agent explicitly archives). In practice this is not a bottleneck. If it becomes one, shard by agent_id.

**Current status**: Acceptable for current scale.

---

### Risk 4: Signals.Buffer counter serialization (current bug)

**Scenario**: `Signals.Buffer` GenServer serializes a monotonic counter increment on every signal. Under high event frequency this creates a bottleneck.

**Mitigation** (AD pending): Replace counter with `:atomics`. The GenServer stays for subscription management only. Counter increments become lock-free.

**Current status**: Known issue, tracked as P3 in architecture audit. Fix is straightforward.

---

## Three-Tier Memory Architecture

```
┌─────────────────────────────────────────┐
│            Agent Context Window          │
│  ┌─────────────┐  ┌────────────────┐    │
│  │ Core Memory │  │ Recall Memory  │    │
│  │ (always in) │  │ (recent convo) │    │
│  └─────────────┘  └────────────────┘    │
└─────────────────────────────────────────┘
           │                │
           ▼                ▼
┌─────────────────────────────────────────┐
│          Memory.Store (ETS + disk)       │
│  ┌───────────────────────────────────┐  │
│  │        Archival Memory            │  │
│  │  (long-term, searched by embed)   │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

Core and recall are small, always loaded into the agent's system prompt. Archival is large, searched on demand via embedding similarity. The Letta memory model allows agents to explicitly archive information and retrieve it later.
