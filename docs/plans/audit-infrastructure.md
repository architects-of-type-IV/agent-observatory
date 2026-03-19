# Infrastructure & Loose Module Audit

**Date**: 2026-03-19
**Scope**: All modules NOT inside the 4 domain directories (`control/`, `observability/`, `projects/`, `mes/`)
**Method**: Read-only. No edits. Function-by-function analysis.

---

## Audit Dimensions (applied to every module)

1. Module name and purpose
2. Every public function with shape
3. Should this be absorbed into a domain?
4. Is this a GenServer that could be a plain module?
5. Shape-duplicate functions elsewhere?
6. Could it become an Ash resource?
7. Dead or near-dead status?

---

## Verdicts key

- **KEEP** — correct placement, no action needed
- **ABSORB** — pull into a domain
- **COLLAPSE** — inline into callsite or merge with another module
- **DEMOTE** — GenServer to plain module
- **EXTRACT** — split shared logic into a new shared module
- **INSPECT** — needs further investigation before judgment
- **DEAD** — zero live callers, delete

---

## Gateway

### `Ichor.Gateway.Channel` (`gateway/channel.ex`)

**Purpose**: Behaviour definition for delivery channels.

**Public API**:
- `channel_key/0 :: atom()` (callback)
- `deliver(String.t(), map()) :: :ok | {:error, term()}` (callback)
- `available?(String.t()) :: boolean()` (callback)
- `skip?(map()) :: boolean()` (optional callback, default false)

**Absorb into domain?** No. Cross-cutting infrastructure behaviour.
**GenServer?** N/A.
**Shape duplicates?** No.
**Ash resource?** No.
**Dead?** No — 4 implementations.

**Verdict**: KEEP

---

### `Ichor.Gateway.Router` (`gateway/router.ex`)

**Purpose**: Broadcast pipeline orchestrator. Resolves address to channel, delivers, returns count.

**Public API**:
- `channels/0 :: [{module(), keyword()}]`
- `broadcast(String.t(), map()) :: {:ok, non_neg_integer()} | {:error, term()}`
- `ingest(map()) :: :ok | {:error, term()}`

**Private of note**: `resolve/1` — pattern-matches "agent:", "session:", "team:", "role:", "fleet:" prefixes.

**Shape duplicates?** YES. `resolve/1` here has the same shape as `resolve_target/1` in `Ichor.MessageRouter`. Both pattern-match on the same prefix strings and return a recipient descriptor. Semantically identical. Must be unified.

**Verdict**: KEEP. EXTRACT `resolve/1` into shared `Ichor.Gateway.AddressResolver`. Delete duplicate in `MessageRouter`.

---

### `Ichor.Gateway.Envelope` (`gateway/envelope.ex`)

**Purpose**: Struct constructor for `{address, payload, metadata}`.

**Public API**: `new(String.t(), map(), keyword()) :: t()`

**Verdict**: KEEP

---

### `Ichor.Gateway.HeartbeatManager` (`gateway/heartbeat_manager.ex`)

**Purpose**: GenServer. Tracks last-seen timestamps per agent. Evicts stale entries on timer every 30s.

**Public API**: `record_heartbeat(String.t(), String.t()) :: :ok`

**Iron Law**: Timer eviction + mutable shared state. Legitimate.
**Dead?** INSPECT — verify `record_heartbeat/2` callers are active.

**Verdict**: KEEP. Verify callers.

---

### `Ichor.Gateway.CronJob` (`gateway/cron_job.ex`)

**Purpose**: Ash Resource. SQLite-persisted scheduled work items per agent.

**Public API** (code_interface): `schedule_once/3`, `for_agent/1`, `all_scheduled/0`, `due/0`, `reschedule/2`, `complete/1`

**Domain**: `Ichor.Control`. Correct placement.

**Verdict**: KEEP

---

### `Ichor.Gateway.CronScheduler` (`gateway/cron_scheduler.ex`)

**Purpose**: GenServer. `Process.send_after` timers per job. Delegates persistence to `CronJob` resource.

**Public API**:
- `schedule_once(String.t(), pos_integer(), term()) :: :ok | {:error, :invalid_delay}`
- `list_jobs(String.t()) :: [CronJob.t()]`
- `list_all_jobs/0 :: [CronJob.t()]`

**Iron Law**: `Process.send_after` timers. Legitimate.

**Verdict**: KEEP. Consider exposing `list_jobs`/`list_all_jobs` via `Ichor.Control` domain to avoid callers depending on the scheduler module directly.

---

### `Ichor.Gateway.WebhookRouter` (`gateway/webhook_router.ex`)

**Purpose**: GenServer. Enqueues, retries, and dead-letters outbound webhook deliveries.

**Public API**:
- `enqueue(String.t(), String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}`
- `list_dead_letters(String.t()) :: [WebhookDelivery.t()]`
- `list_all_dead_letters/0 :: [WebhookDelivery.t()]`
- `compute_signature(String.t(), String.t()) :: String.t()`
- `verify_signature(String.t(), String.t(), String.t()) :: boolean()`

**Iron Law**: Timer-based retry polling loop. Legitimate.

**Note**: `compute_signature/2` and `verify_signature/3` are pure functions embedded in the GenServer. They could move to a `Ichor.Gateway.WebhookSigning` plain module or become private (verify callers).

**Verdict**: KEEP. Consider extracting pure signing functions.

---

### `Ichor.Gateway.WebhookDelivery` (`gateway/webhook_delivery.ex`)

**Purpose**: Ash Resource. SQLite-persisted delivery attempts with retry/dead-letter tracking.

**Public API** (code_interface): `enqueue/4`, `due_for_delivery/0`, `dead_letters_for_agent/1`, `all_dead_letters/0`, `mark_delivered/1`, `schedule_retry/2`, `mark_dead/1`

**Domain**: `Ichor.Control`. Correct.

**Verdict**: KEEP

---

### `Ichor.Gateway.HITLRelay` (`gateway/hitl_relay.ex`)

**Purpose**: GenServer. Human-in-the-loop pause/unpause lifecycle. Buffers messages for paused sessions in ETS. 217 lines.

**Public API**:
- `pause(String.t(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}`
- `unpause(String.t(), String.t(), String.t()) :: :ok | {:error, :not_paused}`
- `rewrite(String.t(), String.t(), String.t()) :: :ok | {:error, :not_paused}`
- `inject(String.t(), String.t(), map()) :: :ok`
- `buffer_message(String.t(), map()) :: :ok`
- `session_status(String.t()) :: :paused | :active`
- `buffered_messages(String.t()) :: [map()]`
- `paused_sessions/0 :: [String.t()]`
- `reject(String.t(), String.t(), String.t()) :: :ok | {:error, :not_paused}`

**Iron Law**: ETS buffer state + sweep timer. Legitimate.

**Verdict**: KEEP

---

### `Ichor.Gateway.HITLInterventionEvent` (`gateway/hitl_intervention_event.ex`)

**Purpose**: Ash Resource. SQLite audit log of HITL events.

**Public API** (code_interface): `record/5`, `by_session/1`, `by_agent/1`, `by_operator/1`, `recent/1`

**Domain**: `Ichor.Observability`. Correct.

**Verdict**: KEEP

---

### `Ichor.Gateway.EntropyTracker` (`gateway/entropy_tracker.ex`)

**Purpose**: GenServer. Sliding-window loop detection per agent session. Scores `{tool_name, tool_input, result}` tuples for repetition.

**Public API**:
- `record_and_score(String.t(), {term(), term(), term()}) :: {:ok, float(), :loop | :warning | :normal} | {:error, :missing_agent_id}`
- `register_agent(String.t(), keyword()) :: :ok`
- `get_window(String.t()) :: [term()]`
- `reset/0 :: :ok`

**Iron Law**: Private ETS table ownership + stateful sliding windows. Legitimate.

**Note**: `compute_score/2` and `slide_window/2` are pure private functions in the GenServer — good, they are already `defp`.

**Verdict**: KEEP

---

### `Ichor.Gateway.TopologyBuilder` (`gateway/topology_builder.ex`)

**Purpose**: GenServer. Builds and publishes a live topology map. PubSub subscriber + sweep timer.

**Public API**: `subscribe_to_session(String.t()) :: :ok`

**Iron Law**: PubSub subscriptions + sweep timer. Legitimate.

**Verdict**: KEEP

---

### `Ichor.Gateway.TmuxDiscovery` (`gateway/tmux_discovery.ex`)

**Purpose**: GenServer. Polls tmux every 5s. Enforces BEAM invariant: every non-infra tmux session must have an AgentProcess.

**Public API**: `infrastructure_session?/1` (helper)

**Iron Law**: Polling loop via Process.send_after. Legitimate.

**Verdict**: KEEP

---

### `Ichor.Gateway.SchemaInterceptor` (`gateway/schema_interceptor.ex`)

**Purpose**: Plain module. Validates and enriches raw event maps against DecisionLog schema.

**Public API**:
- `validate_and_enrich(map()) :: {:ok, DecisionLog.t()} | {:error, Ecto.Changeset.t()}`
- `build_violation_event(Ecto.Changeset.t(), map(), binary() | nil) :: map()`
- `validate_envelope(Envelope.t()) :: :ok | {:error, String.t()}`

**GenServer?** No process needed. Already plain. Correct.

**Verdict**: KEEP

---

### `Ichor.Gateway.EventBridge` (`gateway/event_bridge.ex`)

**Purpose**: GenServer. Subscribes to `:events` signals, transforms to Phoenix PubSub broadcasts for LiveView. Contains `map_intent/3` — a 20+ clause pure dispatch table.

**Public API**: `start_link/1` only.

**Iron Law**: PubSub subscription + stateful last_event tracking + sweep timer. Legitimate.

**Note**: `map_intent/3` is a large pure dispatch table embedded in the GenServer as private `defp` clauses. It should be extracted to a companion `Ichor.Gateway.IntentMapper` plain module to: (a) keep the GenServer under 150 lines, (b) make the mapping table independently testable.

**Verdict**: KEEP. EXTRACT `map_intent/3` to `Ichor.Gateway.IntentMapper`.

---

### `Ichor.Gateway.OutputCapture` (`gateway/output_capture.ex`)

**Purpose**: GenServer. Polls tmux panes on a timer, publishes output diffs.

**Public API**:
- `watch(String.t()) :: :ok`
- `unwatch(String.t()) :: :ok`

**Iron Law**: Timer-based polling per target. Legitimate.
**Dead?** INSPECT — verify `watch/1` callers are active.

**Verdict**: KEEP. Verify callers.

---

### `Ichor.Gateway.Router.EventIngest` (`gateway/router/event_ingest.ex`)

**Purpose**: Plain module. Extracted sub-module of Router. Handles hook event ingestion, side effects, signal emission.

**Public API**: `ingest(map()) :: :ok`

**Verdict**: KEEP

---

### `Ichor.Gateway.Channels.Tmux` (`gateway/channels/tmux.ex`)

**Purpose**: Implements Channel behaviour. Delivers messages to tmux sessions via named buffers. Tries multiple server options (socket, named server, default).

**Public API** (Channel behaviour + extras):
- `channel_key/0`, `deliver/2`, `available?/1`, `skip?/1`
- `capture_pane(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}`
- `list_panes/0 :: [map()]`
- `list_sessions/0 :: [String.t()]`
- `run_command([String.t()]) :: {:ok, String.t()} | {:error, term()}`
- `socket_args/0 :: [String.t()]`

**Shape duplicates?** `strip_ansi/1` (private) is byte-identical to `SshTmux.strip_ansi/1`. Code duplication.

**Verdict**: KEEP. EXTRACT `strip_ansi/1` to `Ichor.Gateway.Channels.AnsiUtils` module.

---

### `Ichor.Gateway.Channels.SshTmux` (`gateway/channels/ssh_tmux.ex`)

**Purpose**: Implements Channel behaviour. Delivers messages to tmux sessions on remote hosts via SSH.

**Public API**:
- `channel_key/0`, `deliver/2`, `available?/1`, `skip?/1`
- `capture_pane(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}`
- `list_sessions(String.t()) :: [String.t()]`

**Shape duplicates?** `strip_ansi/1` — identical to Tmux version.

**Verdict**: KEEP. EXTRACT `strip_ansi/1`.

---

### `Ichor.Gateway.Channels.WebhookAdapter` (`gateway/channels/webhook_adapter.ex`)

**Purpose**: Implements Channel behaviour. Thin wrapper around `WebhookRouter.enqueue/4`.

**Public API**: `channel_key/0`, `deliver/2`, `available?/1`

**Dead?** INSPECT — verify this channel is registered in `Router.channels/0`.

**Verdict**: KEEP (correct pattern for Channel behaviour adapter).

---

### `Ichor.Gateway.Channels.MailboxAdapter` (`gateway/channels/mailbox_adapter.ex`)

**Purpose**: Implements Channel behaviour. Delivers to in-process `AgentProcess` mailboxes.

**Public API**: `channel_key/0`, `deliver/2`, `available?/1`

**Verdict**: KEEP

---

### `Ichor.Gateway.AgentRegistry.AgentEntry` (`gateway/agent_registry/agent_entry.ex`)

**Purpose**: Pure module. Helpers for constructing and interpreting agent registry entries.

**Public API**:
- `new(String.t()) :: map()`
- `short_id(String.t() | nil) :: String.t()`
- `uuid?(String.t()) :: boolean()`
- `role_from_string(String.t() | nil) :: atom()`

**Dead?** INSPECT — verify each function has multiple callsites. If single callsite, collapse into caller.

**Verdict**: KEEP if multiple callsites. COLLAPSE otherwise.

---

### `Ichor.Gateway.Types.HITLAction` (`gateway/types/hitl_action.ex`)

**Purpose**: `Ash.Type.Enum` with values `[:pause, :unpause, :rewrite, :inject]`.

**Verdict**: KEEP

---

### `Ichor.Gateway.Types.DeliveryStatus` (`gateway/types/delivery_status.ex`)

**Purpose**: `Ash.Type.Enum` with values `[:pending, :delivered, :failed, :dead]`.

**Verdict**: KEEP

---

## Archon

### `Ichor.Archon.Chat` (`archon/chat.ex`)

**Purpose**: Plain module. Orchestrates a single chat turn: build context, build chain, run chain.

**Public API**: `chat(String.t(), list()) :: {:ok, String.t() | map(), list()} | {:error, term()}`

**GenServer?** No — stateless, config-injected. Correct.

**Verdict**: KEEP

---

### `Ichor.Archon.Chat.ContextBuilder` (`archon/chat/context_builder.ex`)

**Purpose**: Plain module. Builds system + memory message list. Uses `Task.yield_many` for async memory retrieval.

**Public API**: `build_messages(String.t()) :: {:ok, list()}`

**Verdict**: KEEP

---

### `Ichor.Archon.Chat.ChainBuilder` (`archon/chat/chain_builder.ex`)

**Purpose**: Plain module. Constructs LangChain `LLMChain` with tools and system prompt.

**Public API**: `build() :: {:ok, term()} | {:error, term()}`

**Verdict**: KEEP

---

### `Ichor.Archon.Chat.TurnRunner` (`archon/chat/turn_runner.ex`)

**Purpose**: Plain module. Runs a chain turn, extracts result message.

**Public API**: `run(term(), list(), String.t()) :: {:ok, String.t(), list()} | {:error, term()}`

**Verdict**: KEEP

---

### `Ichor.Archon.Chat.CommandRegistry` (`archon/chat/command_registry.ex`)

**Purpose**: Plain module. Dispatch table (40+ clauses) mapping command names to Ash actions.

**Public API**: `dispatch(map()) :: {:ok, map()} | {:error, term()}`

**Note**: 40+ clauses have grown organically. Consider grouping by sub-domain (agent commands, team commands, memory commands) in future cleanup.

**Verdict**: KEEP

---

### `Ichor.Archon.SignalManager` (`archon/signal_manager.ex`)

**Purpose**: GenServer. Subscribes to all signals, maintains stateful projection of recent signal activity.

**Public API**:
- `snapshot() :: map()`
- `attention() :: [map()]`

**Iron Law**: PubSub subscriptions + stateful projection. Legitimate.
**Dead?** INSPECT — verify callers of `snapshot/0` and `attention/0`.

**Verdict**: KEEP. Verify callers.

---

### `Ichor.Archon.SignalManager.Reactions` (`archon/signal_manager/reactions.ex`)

**Purpose**: Pure module. Maps incoming Signal messages to projection state.

**Public API**:
- `new_state() :: state()`
- `ingest(Message.t(), state()) :: state()`

**Design note**: Exemplary — all pure, all testable. GenServer owns timing, this module owns logic.

**Verdict**: KEEP

---

### `Ichor.Archon.TeamWatchdog` (MISSING)

**Status**: Referenced in `SystemSupervisor` children list. Source file not found in project glob.

**Risk**: If the module does not exist at runtime, the supervisor start will crash the application.

**Action required**: Locate or recreate `Ichor.Archon.TeamWatchdog`. If intentionally removed, delete from `SystemSupervisor` child spec immediately.

**Verdict**: INSPECT (CRITICAL — potential startup crash)

---

### `Ichor.Archon.TeamWatchdog.Reactions` (`archon/team_watchdog/reactions.ex`)

**Purpose**: Pure module. Policy decisions for team watchdog: react to signals, produce action tuples.

**Public API**: `react(atom(), map(), state()) :: {[action()], state()}`

**Verdict**: KEEP (orphaned from missing parent GenServer)

---

### `Ichor.Archon.MemoriesClient` (`archon/memories_client.ex`)

**Purpose**: Plain module. HTTP client for external Memories knowledge graph API. Typed result structs.

**Public API**:
- `search(String.t(), keyword()) :: {:ok, [SearchResult.t()]} | {:error, term()}`
- `ingest(String.t(), keyword()) :: {:ok, IngestResult.t() | ChunkedIngestResult.t()} | {:error, term()}`
- `query_memory(String.t(), keyword()) :: {:ok, QueryResult.t()} | {:error, term()}`
- `group_id/0 :: String.t()`
- `user_id/0 :: String.t()`

**GenServer?** No — stateless HTTP. Correct.

**Verdict**: KEEP

---

### `Ichor.Archon.CommandManifest` (`archon/command_manifest.ex`)

**Purpose**: Plain module. Compile-time catalog of UI quick actions and reference commands.

**Public API**:
- `quick_actions() :: [map()]`
- `reference_commands() :: [{String.t(), String.t()}]`
- `unknown_command_help(String.t()) :: String.t()`

**Verdict**: KEEP

---

## Signals

### `Ichor.Signals.Bus` (`signals/bus.ex`)

**Purpose**: Plain module. Sole PubSub wrapper. All signals route through here.

**Public API**:
- `subscribe(String.t()) :: :ok | {:error, term()}`
- `unsubscribe(String.t()) :: :ok`
- `broadcast(String.t(), term()) :: :ok | {:error, term()}`

**Verdict**: KEEP

---

### `Ichor.Signals.Buffer` (`signals/buffer.ex`)

**Purpose**: GenServer. ETS ring buffer of recent signals. Re-broadcasts for late subscribers.

**Public API**: `recent(non_neg_integer()) :: [{non_neg_integer(), Message.t()}]`

**Iron Law**: ETS table ownership + PubSub subscription. Legitimate.

**Verdict**: KEEP

---

### `Ichor.Signals.Catalog` (`signals/catalog.ex`)

**Purpose**: Plain module. Compile-time signal definitions and category queries.

**Public API**: `lookup/1`, `lookup!/1`, `derive/1`, `valid_category?/1`, `categories/0`, `all/0`, `by_category/1`, `static_signals/0`, `dynamic_signals/0`

**Verdict**: KEEP

---

### `Ichor.Signals.FromAsh` (`signals/from_ash.ex`)

**Purpose**: `Ash.Notifier`. Maps resource mutations to signal emissions. 13 resources wired.

**Public API**: `notify/1` (Ash.Notifier callback)

**Verdict**: KEEP

---

### `Ichor.Signals.Runtime` (`signals/runtime.ex`)

**Purpose**: Implements `Signals.Behaviour`. Primary emit/subscribe/unsubscribe API.

**Public API**: `emit/2`, `emit/3`, `subscribe/1`, `subscribe/2`, `unsubscribe/1`, `unsubscribe/2`, `category_topic/1`, `categories/0`

**Verdict**: KEEP

---

### `Ichor.Signals.Event` (`signals/event.ex`)

**Purpose**: Ash Resource using `Ash.DataLayer.Simple`. Exposes runtime signal operations through the Ash action model without persistence.

**Actions**: `emit`, `emit_scoped`, `recent`, `catalog`

**Pattern note**: Excellent use of `Ash.DataLayer.Simple` for runtime-only Ash Resources that benefit from Ash action/policy model.

**Verdict**: KEEP

---

## MemoryStore

### `Ichor.MemoryStore.Tables` (`memory_store/tables.ex`)

**Purpose**: Plain module. ETS table name constants.

**Verdict**: KEEP

---

### `Ichor.MemoryStore.Blocks` (`memory_store/blocks.ex`)

**Purpose**: Plain module. ETS-backed block operations: CRUD, resolve, compile.

**Public API**: `max_blocks_reached?/0`, `get/1`, `list/1`, `create/1`, `create_many/1`, `update/2`, `save_value/2`, `delete/1`, `resolve/1`, `find_agent_block/2`, `writable?/1`, `compile/1`

**Note**: All functions access ETS directly. The GenServer wrapper in `MemoryStore` adds serialization overhead with no correctness benefit for reads.

**Verdict**: KEEP

---

### `Ichor.MemoryStore.Recall` (`memory_store/recall.ex`)

**Purpose**: Plain module. ETS-backed recall (recent conversation) operations.

**Public API**: `get/1`, `add/4`, `search/3`, `search_by_date/4`

**Verdict**: KEEP

---

### `Ichor.MemoryStore.Archival` (`memory_store/archival.ex`)

**Purpose**: Plain module. ETS-backed archival memory operations.

**Public API**: `get/1`, `count/1`, `insert/3`, `search/3`, `delete/2`, `list/2`

**Verdict**: KEEP

---

### `Ichor.MemoryStore.Persistence` (`memory_store/persistence.ex`)

**Purpose**: Plain module. Disk I/O: load from JSONL, flush dirty entries.

**Public API**: `load_from_disk/0`, `load_jsonl/1`, `flush_dirty/1`

**Verdict**: KEEP

---

### `Ichor.MemoryStore` (`memory_store.ex`)

**Purpose**: GenServer. Serializes ALL ETS access for the memory system. ~500 lines. Every call goes through `GenServer.call/cast`.

**Public API** (full): `create_block`, `get_block`, `update_block`, `delete_block`, `list_blocks`, `create_agent`, `get_agent`, `attach_block`, `detach_block`, `list_agents`, `read_core_memory`, `compile_memory`, `memory_replace`, `memory_insert`, `memory_rethink`, `add_recall`, `conversation_search`, `conversation_search_date`, `archival_memory_insert`, `archival_memory_search`, `archival_memory_delete`, `archival_memory_list`

**Iron Law check**:
- Mutable state across calls? ETS is the state and it is accessible directly by sub-modules without the GenServer.
- Concurrent execution? ETS is natively concurrent.
- Fault isolation? ETS survives process crashes — a restart of the GenServer does NOT protect data.

**Analysis**: The sub-modules (Blocks, Recall, Archival) already read and write ETS directly. The GenServer is a serialization bottleneck with no correctness benefit. Its only legitimate value is: dirty-flag tracking for the disk flush schedule. Pure reads (get_block, list_blocks, conversation_search, etc.) could bypass the GenServer entirely.

**GenServer → plain?** YES. This is the ETS serialization anti-pattern.

**Recommended refactor**: Remove the GenServer. Call sub-modules directly everywhere. Schedule disk flush via a separate lightweight GenServer or `Process.send_after` loop that checks an ETS dirty flag atomically. This is a substantial refactor but eliminates a critical bottleneck.

**Verdict**: DEMOTE

---

## Mesh

### `Ichor.Mesh.CausalDAG` (`mesh/causal_dag.ex`)

**Purpose**: GenServer. Per-session dynamic ETS tables tracking causal relationships between signal events. Orphan buffering, cycle detection.

**Public API**:
- `insert(map(), map()) :: :ok | {:error, :cycle_detected}`
- `get_session_dag(String.t()) :: map()`
- `get_children(String.t(), String.t()) :: [node()]`
- `signal_terminal(String.t()) :: :ok`
- `reset/0 :: :ok`

**Iron Law**: Per-session dynamic ETS table creation + multiple timers. Legitimate.

**Ash resource?** No — dynamic graph tracking is not suitable for Ash.

**Verdict**: KEEP

---

### `Ichor.Mesh.DecisionLog` (`mesh/decision_log.ex`)

**Purpose**: Ecto embedded schema (NOT DB-persisted). Validation and transport struct for gateway events. Contains 6 embedded sub-schemas.

**Public API**:
- `changeset(t(), map()) :: Ecto.Changeset.t()`
- `root?/1 :: boolean()`
- `major_version/1 :: integer()`
- `put_gateway_entropy_score/2 :: t()`
- `from_json/1 :: {:ok, t()} | {:error, Ecto.Changeset.t()}`

**Ash resource?** Could become `Ash.Resource` with `Ash.DataLayer.Simple`, but the Ecto embedded schema is cleaner for a pure validation+transport struct with no persistence need.

**Verdict**: KEEP

---

## Tasks

### `Ichor.Tasks.Board` (`tasks/board.ex`)

**Purpose**: Plain module. Thin orchestration layer: wraps TeamStore CRUD + emits signals.

**Public API**:
- `create_task(String.t(), map()) :: {:ok, map()} | {:error, term()}`
- `update_task(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}`
- `delete_task(String.t(), String.t()) :: :ok | {:error, term()}`
- 3 `defdelegate` calls to TeamStore (get_task, list_tasks, next_task_id)

**Analysis**: The only value added by Board over TeamStore is signal emission on the 3 write operations. This is a near-dead thin wrapper — one layer of indirection for three extra `Signals.emit` calls.

**Verdict**: COLLAPSE. Inline signal emission into TeamStore write functions. Delete Board. Callers call TeamStore directly.

---

### `Ichor.Tasks.JsonlStore` (`tasks/jsonl_store.ex`)

**Purpose**: Plain module. File mutation using jq and shell scripts.

**Public API**: `heal_task/2`, `reassign_task/3`, `claim_task/3`, `update_task_status/4`

**Verdict**: KEEP

---

### `Ichor.Tasks.TeamStore` (`tasks/team_store.ex`)

**Purpose**: Plain module. File-based CRUD under `~/.claude/tasks/`.

**Public API**: `create_task/2`, `update_task/3`, `get_task/2`, `list_tasks/1`, `delete_task/2`, `next_task_id/1`

**Verdict**: KEEP

---

## AgentWatchdog

### `Ichor.AgentWatchdog` (`agent_watchdog.ex`)

**Purpose**: GenServer. Consolidated health monitor. Subscribes to `:events` signals, 5s tick. Handles heartbeat checking, crash detection, pane scanning, escalation.

**Public API**: `start_link/1` only.

**Iron Law**: Timer + PubSub subscription + stateful tracking. Legitimate.

**Verdict**: KEEP

---

### `Ichor.AgentWatchdog.NudgePolicy` (`agent_watchdog/nudge_policy.ex`)

**Purpose**: Pure module. Escalation policy decisions.

**Public API**: `stale?/3`, `agent_session_id/1`, `effective_max_level/2`, `default_entry/2`, `process_escalations/6`

**Design note**: Exemplary — pure logic extracted from GenServer. All testable without a process.

**Verdict**: KEEP

---

### `Ichor.AgentWatchdog.PaneParser` (`agent_watchdog/pane_parsing.ex`)

**Purpose**: Pure module. Parses tmux pane output for status signals.

**Public API**: `diff_output/2`, `resolve_capture_target/1`, `match_done/1`, `match_blocked/1`

**Verdict**: KEEP

---

### `Ichor.AgentWatchdog.EventState` (`agent_watchdog/event_state.ex`)

**Purpose**: Pure module. Session activity state transformations.

**Public API**: `extract_team_name/1`, `update_session_activity/2`, `touch_session_activity/2`

**Verdict**: KEEP

---

## Loose Top-Level Modules

### `Ichor.EventBuffer` (`event_buffer.ex`)

**Purpose**: GenServer. Owns ETS table of hook events indexed by session. Tool duration tracking, session alias resolution, tombstone management.

**Public API**: `ingest/1`, `list_events/0`, `latest_per_session/0`, `unique_project_cwds/0`, `remove_session/1`, `tombstone_session/1`, `events_for_session/1`

**Iron Law**: ETS table ownership + tombstone state + tool duration accumulation across calls. Legitimate.

**Verdict**: KEEP

---

### `Ichor.MemoriesBridge` (`memories_bridge.ex`)

**Purpose**: GenServer. Buffers signals and flushes to external Memories API. Self-disables if API key not configured.

**Public API**:
- `enabled?/0 :: boolean()`
- `stats/0 :: map()`

**Iron Law**: Flush timer + PubSub subscription + buffering state. Legitimate.

**Verdict**: KEEP

---

### `Ichor.Notes` (`notes.ex`)

**Purpose**: Plain module with ETS backing. Key-value note store. `init/0` called at application startup.

**Public API**: `init/0`, `add_note/2`, `get_note/1`, `list_notes/0`, `delete_note/1`

**GenServer?** No process needed. ETS initialized at startup. Correct pattern.

**Dead?** INSPECT — verify callers beyond REPL.

**Verdict**: KEEP

---

### `Ichor.ProtocolTracker` (`protocol_tracker.ex`)

**Purpose**: GenServer. Tracks message delivery events. Provides protocol statistics for ops dashboard.

**Public API**:
- `get_traces/0 :: [map()]`
- `get_stats/0 :: map()`
- `track_mailbox_delivery(String.t(), String.t(), String.t()) :: :ok`
- `track_command_write(String.t(), String.t()) :: :ok`
- `track_gateway_broadcast/1 :: :ok`

**Iron Law**: PubSub subscription + stateful trace accumulation. Legitimate.

**Dead code inside**: `get_stats/0` returns `command_queue:` stats hardcoded to 0. This field is never populated. Either wire it or remove it.

**Verdict**: KEEP. Remove or wire `command_queue` stat.

---

### `Ichor.QualityGate` (`quality_gate.ex`)

**Purpose**: GenServer. Listens for `:TaskCompleted` hook events, calls external quality check API.

**Public API**: `check(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}`

**Iron Law**: PubSub subscription + async call handling. Legitimate.

**Cross-domain**: Uses `Ichor.Projects.Status.state()`. Dependency direction is fine.

**Dead?** INSPECT. `:TaskCompleted` is a `hook_event_type` value from Claude's hook system. Verify that this event type is actually emitted in practice. If nothing emits `:TaskCompleted`, this GenServer never processes anything.

**Verdict**: INSPECT. Trace whether `:TaskCompleted` is ever emitted.

---

### `Ichor.MessageRouter` (`message_router.ex`)

**Purpose**: Plain module. Direct message delivery authority. ETS message log.

**Public API**:
- `send(map()) :: {:ok, map()} | {:error, String.t()}`
- `start_message_log/0` — creates ETS table (called from Application)
- `recent_messages(String.t()) :: [map()]`

**Shape duplicates**: `resolve_target/1` in this module has the SAME shape as `resolve/1` in `Gateway.Router`. Both pattern-match on identical prefix strings ("team:", "fleet:all", "role:", "session:", "agent:") and return a recipient descriptor. This is the most significant code duplication in the codebase.

**Verdict**: KEEP the module. EXTRACT `resolve_target/1` into a shared `Ichor.Gateway.AddressResolver` that both modules call. If address format changes, it must only change in one place.

---

### `Ichor.ObservationSupervisor` (`observation_supervisor.ex`)

**Purpose**: Supervisor. `rest_for_one` strategy. Children: `CausalDAG -> TopologyBuilder -> EventBridge`.

**Design note**: `rest_for_one` is correct here — TopologyBuilder subscribes to CausalDAG output, EventBridge to TopologyBuilder output. Order-dependent restart is semantically correct.

**Verdict**: KEEP

---

### `Ichor.SystemSupervisor` (`system_supervisor.ex`)

**Purpose**: Supervisor. `one_for_one` strategy. 17 children.

**Critical**: References `Ichor.Archon.TeamWatchdog` which has no source file. Potential application startup crash.

**Verdict**: INSPECT. Verify `Ichor.Archon.TeamWatchdog` module exists at runtime.

---

### `Ichor.Application` (`application.ex`)

**Purpose**: OTP Application entry point. Defines startup order, calls one-time ETS initializers inline.

**Note**: `AgentLaunch.init_counter()`, `MessageRouter.start_message_log()`, `Notes.init()` called inline — correct pattern for ETS initialization without a process.

**Verdict**: KEEP

---

### `Ichor.Observability` (`observability.ex`)

**Purpose**: Ash Domain. Resources: Event, Session, Message, Task, Error, Signals.Event, HITLInterventionEvent.

**Verdict**: KEEP

---

### `Ichor.Control` (`control.ex`)

**Purpose**: Ash Domain. Resources: Agent, Team, TeamBlueprint, AgentBlueprint, AgentType, SpawnLink, CommRule, WebhookDelivery, CronJob.

**Verdict**: KEEP

---

## Summary of Findings

### Critical (act before next refactor phase)

| # | Finding | Action |
|---|---------|--------|
| 1 | `Ichor.Archon.TeamWatchdog` GenServer file MISSING | Locate or remove from `SystemSupervisor` — potential startup crash |
| 2 | `Gateway.Router.resolve/1` and `MessageRouter.resolve_target/1` are shape-duplicates with identical logic | EXTRACT to `Ichor.Gateway.AddressResolver` |
| 3 | `Tmux.strip_ansi/1` and `SshTmux.strip_ansi/1` are byte-identical private functions | EXTRACT to `Ichor.Gateway.Channels.AnsiUtils` |

### High Priority (next refactor wave)

| # | Finding | Action |
|---|---------|--------|
| 4 | `Ichor.MemoryStore` GenServer serializes reads that sub-modules handle directly via ETS | DEMOTE: remove GenServer, call sub-modules directly, separate flush timer |
| 5 | `Ichor.Tasks.Board` is a thin wrapper that only adds signal emission to 3 write operations | COLLAPSE: inline signal emission into TeamStore, delete Board |
| 6 | `ProtocolTracker.get_stats/0` has `command_queue` field hardcoded to 0 | Remove field or wire it |

### Medium Priority (verify + decide)

| # | Finding | Action |
|---|---------|--------|
| 7 | `QualityGate` listens for `:TaskCompleted` — verify this hook_event_type is ever emitted | Trace emitters |
| 8 | `OutputCapture` — verify `watch/1` callers are active | Trace callers |
| 9 | `SignalManager` — verify `snapshot/0` and `attention/0` callers are active | Trace callers |
| 10 | `HeartbeatManager.record_heartbeat/2` — verify callers are active | Trace callers |
| 11 | `AgentRegistry.AgentEntry` — verify each function has multiple callsites | Count callers |

### Low Priority (cosmetic / future)

| # | Finding | Action |
|---|---------|--------|
| 12 | `EventBridge.map_intent/3` is a 20+ clause pure dispatch embedded in GenServer | EXTRACT to `Ichor.Gateway.IntentMapper` for testability |
| 13 | `WebhookRouter.compute_signature/verify_signature` are pure in a GenServer | Move to `Ichor.Gateway.WebhookSigning` or make private |
| 14 | `CommandRegistry` 40+ clauses — organize by sub-domain | Group in future cleanup |
| 15 | `CronScheduler.list_jobs/list_all_jobs` bypass domain — expose via `Ichor.Control` | Add domain delegation |

---

## Module Classification Table

| Module | Type | Verdict |
|--------|------|---------|
| Gateway.Channel | Behaviour | KEEP |
| Gateway.Router | Plain | KEEP + EXTRACT resolve |
| Gateway.Envelope | Plain struct | KEEP |
| Gateway.HeartbeatManager | GenServer (timer) | KEEP, verify callers |
| Gateway.CronJob | Ash Resource | KEEP |
| Gateway.CronScheduler | GenServer (timer) | KEEP |
| Gateway.WebhookRouter | GenServer (timer) | KEEP |
| Gateway.WebhookDelivery | Ash Resource | KEEP |
| Gateway.HITLRelay | GenServer (ETS+timer) | KEEP |
| Gateway.HITLInterventionEvent | Ash Resource | KEEP |
| Gateway.EntropyTracker | GenServer (ETS) | KEEP |
| Gateway.TopologyBuilder | GenServer (pubsub+timer) | KEEP |
| Gateway.TmuxDiscovery | GenServer (poll timer) | KEEP |
| Gateway.SchemaInterceptor | Plain | KEEP |
| Gateway.EventBridge | GenServer (pubsub+timer) | KEEP + EXTRACT IntentMapper |
| Gateway.OutputCapture | GenServer (poll timer) | KEEP, verify callers |
| Gateway.Router.EventIngest | Plain | KEEP |
| Gateway.Channels.Tmux | Channel impl | KEEP + EXTRACT strip_ansi |
| Gateway.Channels.SshTmux | Channel impl | KEEP + EXTRACT strip_ansi |
| Gateway.Channels.WebhookAdapter | Channel impl | KEEP, verify registered |
| Gateway.Channels.MailboxAdapter | Channel impl | KEEP |
| Gateway.AgentRegistry.AgentEntry | Pure helpers | KEEP (verify callers) |
| Gateway.Types.HITLAction | Ash.Type.Enum | KEEP |
| Gateway.Types.DeliveryStatus | Ash.Type.Enum | KEEP |
| Archon.Chat | Plain | KEEP |
| Archon.Chat.ContextBuilder | Plain | KEEP |
| Archon.Chat.ChainBuilder | Plain | KEEP |
| Archon.Chat.TurnRunner | Plain | KEEP |
| Archon.Chat.CommandRegistry | Plain | KEEP |
| Archon.SignalManager | GenServer (pubsub) | KEEP, verify callers |
| Archon.SignalManager.Reactions | Pure | KEEP |
| Archon.TeamWatchdog | GenServer | INSPECT (file missing) |
| Archon.TeamWatchdog.Reactions | Pure | KEEP |
| Archon.MemoriesClient | Plain (HTTP) | KEEP |
| Archon.CommandManifest | Plain (compile-time) | KEEP |
| Signals.Bus | Plain | KEEP |
| Signals.Buffer | GenServer (ETS+pubsub) | KEEP |
| Signals.Catalog | Plain (compile-time) | KEEP |
| Signals.FromAsh | Ash.Notifier | KEEP |
| Signals.Runtime | Plain | KEEP |
| Signals.Event | Ash Resource (Simple) | KEEP |
| MemoryStore.Tables | Plain (constants) | KEEP |
| MemoryStore.Blocks | Plain (ETS) | KEEP |
| MemoryStore.Recall | Plain (ETS) | KEEP |
| MemoryStore.Archival | Plain (ETS) | KEEP |
| MemoryStore.Persistence | Plain (disk I/O) | KEEP |
| MemoryStore | GenServer (ETS serial.) | DEMOTE |
| Mesh.CausalDAG | GenServer (dynamic ETS) | KEEP |
| Mesh.DecisionLog | Ecto embedded schema | KEEP |
| Tasks.Board | Plain (thin wrapper) | COLLAPSE into TeamStore |
| Tasks.JsonlStore | Plain (file/shell) | KEEP |
| Tasks.TeamStore | Plain (file) | KEEP |
| AgentWatchdog | GenServer (timer+pubsub) | KEEP |
| AgentWatchdog.NudgePolicy | Pure | KEEP |
| AgentWatchdog.PaneParser | Pure | KEEP |
| AgentWatchdog.EventState | Pure | KEEP |
| EventBuffer | GenServer (ETS) | KEEP |
| MemoriesBridge | GenServer (timer+pubsub) | KEEP |
| Notes | Plain (ETS) | KEEP |
| ProtocolTracker | GenServer (pubsub) | KEEP + fix dead stat |
| QualityGate | GenServer (pubsub) | INSPECT (verify emitters) |
| MessageRouter | Plain (ETS) | KEEP + EXTRACT resolve |
| ObservationSupervisor | Supervisor | KEEP |
| SystemSupervisor | Supervisor | INSPECT (missing child) |
| Application | OTP Application | KEEP |
| Observability (domain) | Ash Domain | KEEP |
| Control (domain) | Ash Domain | KEEP |

---

*End of audit. All findings are research-only. No files were modified.*
