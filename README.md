# memory_store

Three-tier memory for long-running agents: pinned context blocks, searchable
conversation history, and an unbounded archival store.

Extracted from the ICHOR IV agent observatory. Modelled on Letta's memory
design, but with no vector database, no external services, and no dependencies —
ETS for hot reads, JSON and JSONL files for durability.

## The three tiers

| Tier | Analogy | What it holds |
|---|---|---|
| **Core** | RAM | Named blocks pinned into the agent's context — the working set it always sees |
| **Recall** | Conversation log | Chronological messages, searchable by substring or date range |
| **Archival** | Disk | Unbounded tagged passages the agent writes and searches deliberately |

Core blocks are addressed by id and can be attached to several agents at once,
so a shared "organization" block stays consistent across a fleet — edit it
through one agent and every other agent sees the change.

## Install

```elixir
def deps do
  [{:memory_store, path: "../memory_store"}]
end
```

Requires Elixir 1.18+ for the built-in `JSON` module, which is what keeps the
project dependency-free.

Add it to your supervision tree:

```elixir
children = [MemoryStore]
```

## Use

```elixir
{:ok, _} = MemoryStore.create_agent("scout", [
  %{label: "persona", value: "You survey codebases.", description: "Who I am"},
  %{label: "human",   value: "Prefers terse answers."}
])

# Agent-facing edit tools
{:ok, _} = MemoryStore.memory_rethink("scout", "human", "Prefers detail.")
{:ok, _} = MemoryStore.memory_replace("scout", "persona", "survey", "audit")
{:ok, _} = MemoryStore.memory_insert("scout", "persona", 0, "Rule zero.")

# Render for a system prompt
{:ok, text} = MemoryStore.compile_memory("scout")
#=> <memory_block label="persona" read_only="false">
#=>   <!-- Who I am -->
#=>   You audit codebases.
#=>   </memory_block>

# Recall
{:ok, _} = MemoryStore.add_recall("scout", :user, "deploy the service")
{:ok, hits} = MemoryStore.conversation_search("scout", "deploy")
{:ok, hits} = MemoryStore.conversation_search_date("scout", from, to)

# Archival
{:ok, _} = MemoryStore.archival_memory_insert("scout", "Repo uses Ash.", ["stack"])
{:ok, hits} = MemoryStore.archival_memory_search("scout", "ash", tags: ["stack"])
```

### Sharing a block between agents

```elixir
{:ok, org} = MemoryStore.create_block(%{label: "org", value: "Acme"})
{:ok, _} = MemoryStore.create_agent("scout", [%{label: "persona"}], [org.id])
{:ok, _} = MemoryStore.create_agent("builder", [], [org.id])

MemoryStore.memory_rethink("scout", "org", "Acme Corp")
# builder sees "Acme Corp" too
```

`read_only: true` blocks reject the agent-facing tools (`memory_replace`,
`memory_insert`, `memory_rethink`) with `{:error, :read_only}`, while
`update_block/2` still works — so the host application can edit what the agent
cannot.

## Persistence

```
<data_dir>/
  blocks/<block_id>.json        one file per block; shared, so not under an agent
  agents/<name>/agent.json      the agent record and its block ids
  agents/<name>/recall.jsonl    conversation history, oldest first
  agents/<name>/archival.jsonl  archival passages, oldest first
```

Writes land in ETS immediately and flush to disk on a timer, and again on clean
shutdown. Only records touched since the last flush are rewritten. A hard kill
can lose up to one flush interval — call `MemoryStore.flush/0` for a durability
point.

JSONL files are oldest-first so they read as an append log; ETS holds entries
newest-first for cheap prepends. Recall and archival files are rewritten in
full rather than appended, so a deleted passage actually disappears.

### Bounded ETS, unbounded disk

ETS keeps the newest `recall_limit` and `archival_ets_limit` entries per agent.
Once archival is at capacity, searches and counts read the JSONL file instead,
so older passages stay findable rather than silently dropping out of results.
Recall search does not fall back to disk — it covers the ETS window only.

## Configuration

Everything has a default; none of this is required.

```elixir
config :memory_store,
  data_dir: "~/.memory_store",
  flush_interval_ms: 10_000,
  default_block_limit: 2_000,
  recall_limit: 200,
  archival_ets_limit: 500,
  max_agents: 100,
  max_blocks: 1_000,
  notifier: MemoryStore.Notifier.Noop
```

`MemoryStore` is a singleton — one named process over named ETS tables — so
configuration is application env rather than per-instance options. Set
`:data_dir` before starting the process.

## Notifications

`MemoryStore.Notifier` is how the store tells a host application that memory
changed, without depending on the host's event system:

```elixir
defmodule MyApp.MemoryNotifier do
  @behaviour MemoryStore.Notifier

  @impl true
  def notify(event, agent_name, payload) do
    Phoenix.PubSub.broadcast(MyApp.PubSub, "memory", {event, agent_name, payload})
  end
end

config :memory_store, notifier: MyApp.MemoryNotifier
```

Events are `:agent_created` and `:archival_insert`. They fire after the mutation
is applied, from inside the store process — so a slow implementation blocks the
store, and the result is ignored. Do not route work that must not be lost
through here.

`MemoryStore.Notifier.ProcessMessage` ships as a ready-made adapter that sends
`{:memory_store, event, agent_name, payload}` to a configured pid or registered
name.

## Tests

```
mix test
```

103 tests covering all three tiers, block sharing, limits, persistence
round-trips, and recovery from corrupt files on disk.

## Changes from the original

- Namespace `Ichor.MemoryStore.*` → `MemoryStore.*`.
- `Ichor.Events.emit/1` replaced by the `MemoryStore.Notifier` behaviour,
  defaulting to a no-op, which removes the dependency on a signal bus.
- Jason replaced with the built-in `JSON` module. Block and agent files are now
  written compact rather than pretty-printed.
- Data directory and every limit moved from module attributes to configuration.
- ETS table names are prefixed `memory_store_` rather than `letta_`.

Fixed along the way:

- **Block order was reversed.** `create_agent/3` reversed the list of blocks it
  had just created, so `["persona", "human"]` compiled as `human` then
  `persona`. Order is now preserved.
- **Emptying a log left stale entries on disk.** Recall and archival files were
  only written when the entry list was non-empty, so deleting the last passage
  left the old file in place and it reloaded on restart. An emptied log now
  removes the file.
- **Shutdown lost up to one flush interval.** The store now traps exits and
  flushes in `terminate/2`; `flush/0` exposes a synchronous flush.
- **`created_at` and `updated_at` differed on a new block**, because the clock
  was read twice. One read now, so a fresh block compares equal.
