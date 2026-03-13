---
type: phase
id: 6
title: swarm-memory
date: 2026-03-13
status: pending
links:
  adr: []
depends_on:
  - phase: 5
---

# Phase 6: Swarm Memory Integration

## Overview

This phase bridges the Ichor fleet into the Memories bi-temporal knowledge graph. The write path already exists (MemoriesBridge converts the signal stream into narrated episodes). This phase builds the read path: fleet agents get graph search/write/query tools via MCP, agent sessions map to Memories threads for cross-session continuity, and spawned agents receive role-specific memory packets injected into their instruction overlays before they start working.

No new GenServers are introduced. GraphMemory and GraphThread are stateless Ash resources with inline `run/2` callbacks that call MemoriesClient HTTP. ThreadRegistry is a named ETS table with pure function accessors. MemoryPacket is a pure function module. All graph calls are guarded by `MemoriesBridge.enabled?/0` and degrade gracefully when Memories is unconfigured.

Space strategy (write path only -- search has no space filtering): `project:ichor:fleet` (shared), `project:ichor:agent:{session_id}` (per-agent), `project:ichor:team:{name}` (per-team), `project:ichor:{category}` (signal-derived, existing).

---

## 6.1 Graph Access MCP Tools

- [ ] **Section 6.1 Complete**

Give fleet agents read/write access to the Memories knowledge graph through 3 new MCP tools exposed via the AgentTools Ash domain. Each tool delegates to MemoriesClient HTTP. Write tools use space-scoped namespacing; search operates across the full tenant graph (the Memories `graph_search` action has no `space` argument). Follows the exact Ash resource pattern from `lib/ichor/agent_tools/memory.ex`.

### 6.1.1 GraphMemory Ash Resource

- [ ] **Task 6.1.1 Complete**
- **Governed by:** SWARM_MEMORY.md points 1, 4, 10, 15
- **Parent UCs:** —

Create the `Ichor.AgentTools.GraphMemory` Ash resource with 3 actions that delegate to `Ichor.Archon.MemoriesClient`. The write action (`graph_remember`) accepts `session_id` for space derivation; default write space is `project:ichor:agent:{session_id}`. The search action (`graph_search`) searches across the full tenant graph (no space filtering -- the Memories `graph_search` API does not accept a `space` argument).

- [ ] 6.1.1.1 Create `lib/ichor/agent_tools/graph_memory.ex` with `use Ash.Resource, domain: Ichor.AgentTools`. Add `action :graph_search, :map` with arguments: `session_id :string (allow_nil?: false)`, `query :string (allow_nil?: false)`, `scope :string` (default "edges"), `limit :integer` (default 5). The `run/2` calls `MemoriesClient.search(query, scope: scope, limit: limit)` and returns `{:ok, result}` or formats error. Note: search operates across the full tenant graph; space filtering is not supported by the Memories graph_search API. **VERIFIED:** `MemoriesClient.search/2` always sends `user_id` -- this is required because the Memories `graph_search` implementation crashes (500) when `user_id` is nil. Description: "Search the shared knowledge graph for facts, entities, or past episodes relevant to your task." `done_when: "mix compile --warnings-as-errors"`
- [ ] 6.1.1.2 Add `action :graph_remember, :map` with arguments: `session_id :string (allow_nil?: false)`, `content :string (allow_nil?: false)`, `space :string` (optional). The `run/2` calls `MemoriesClient.ingest(content, type: "text", source: "agent", space: space || "project:ichor:agent:#{session_id}")`. Description: "Write an observation, decision, or outcome to the persistent knowledge graph. Include what you did, what you decided, what failed, and what succeeded." `done_when: "mix compile --warnings-as-errors"`
- [ ] 6.1.1.3 Add `action :graph_query, :map` with arguments: `query :string (allow_nil?: false)`, `limit :integer` (default 5). The `run/2` calls `MemoriesClient.query_memory(query, limit: limit)`. Description: "Ask a question and get an LLM-grounded answer from the knowledge graph with citations." `done_when: "mix compile --warnings-as-errors"`

### 6.1.2 Wire GraphMemory into AgentTools Domain

- [ ] **Task 6.1.2 Complete**
- **Governed by:** SWARM_MEMORY.md point 1
- **Parent UCs:** —

Register GraphMemory in the AgentTools Ash domain so the 3 actions appear as MCP tools for fleet agents.

- [ ] 6.1.2.1 In `lib/ichor/agent_tools.ex`, add `GraphMemory` to the alias list (alongside Inbox, Tasks, Memory, etc.) and add `resource(GraphMemory)` to the `resources do` block `done_when: "mix compile --warnings-as-errors"`
- [ ] 6.1.2.2 In `lib/ichor/agent_tools.ex`, add 3 tool registrations to the `tools do` block: `tool(:graph_search, GraphMemory, :graph_search)`, `tool(:graph_remember, GraphMemory, :graph_remember)`, `tool(:graph_query, GraphMemory, :graph_query)`. Place them in a `# Graph memory` comment group after the `# Archival` group `done_when: "mix compile --warnings-as-errors"`

### 6.1.3 Graph Memory Overlay Instructions

- [ ] **Task 6.1.3 Complete**
- **Governed by:** SWARM_MEMORY.md points 10, 15
- **Parent UCs:** —

Add a graph memory protocol section to the instruction overlay so spawned agents know they have graph tools and when to use them. Include for builder/lead/reviewer roles only (not scout, which is read-only and should not write to the graph).

- [ ] 6.1.3.1 In `lib/ichor/instruction_overlay.ex`, add `defp graph_memory_section(capability)` that returns a markdown section for capabilities in `["builder", "lead", "reviewer"]` and returns `nil` for all others. The section text instructs agents to: (1) call `graph_search` with task description before starting work, (2) call `graph_remember` with outcomes after completing work. Include the space strategy explanation. `done_when: "mix compile --warnings-as-errors"`
- [ ] 6.1.3.2 In `lib/ichor/instruction_overlay.ex`, add `graph_memory_section(capability)` to the list in `generate/1` between `communication_section(name, opts[:team_name])` and `completion_section(capability, gates)` `done_when: "mix compile --warnings-as-errors"`

---

## 6.2 Thread Continuity

- [ ] **Section 6.2 Complete**

Map agent sessions to Memories threads so cross-agent mission continuity works automatically. When agent A finishes and agent B picks up the same mission, B gets A's accumulated context (facts, decisions, episodes) from the thread. Uses the Memories Thread API (POST /api/threads, POST /api/threads/:id/messages, GET /api/threads/:id/context, POST /api/threads/:id/end).

### 6.2.1 MemoriesClient Thread API Extensions

- [ ] **Task 6.2.1 Complete**
- **Governed by:** SWARM_MEMORY.md points 3, 11
- **Parent UCs:** —

Extend the existing MemoriesClient with 4 Thread API functions and 2 new HTTP helpers (`post_crud/3` for standard CRUD actions, `get/1` for GET endpoints). The Memories Thread API is fully available but currently unused by Ichor.

**IMPORTANT -- CRUD vs generic action format:** `POST /api/threads` is a standard Ash `:create` action (not a generic action). AshJsonApi CRUD requires `{"data": {"type": "thread", "attributes": {...}}}` format. The existing `post/2` helper sends the flat generic-action format `{"data": {...}}` which will 400 on CRUD endpoints. A separate `post_crud/3` helper is needed. The other 3 thread endpoints (`add_message`, `get_context`, `end_thread`) are generic actions and use the existing `post/2` / new `get/1`.

- [ ] 6.2.1.0 In `lib/ichor/archon/memories_client.ex`, add 3 response structs for thread operations (following the pattern of the existing `IngestResult`, `SearchResult`, `QueryResult` structs): `ThreadResult` with fields `id :string`, `name :string | nil`, `ended_at :string | nil`; `MessageResult` with fields `id :string`, `thread_id :string`, `role :string`, `content :string`, `episode_id :string | nil`, `metadata :map | nil`, `inserted_at :string | nil`; `ContextResult` with fields `context_text :string | nil`, `facts :list | nil`, `entities :list | nil`, `episodes :list | nil`, `citations :list | nil`, `conversation_history :list | nil`, `token_estimate :integer | nil`. Also add `defp get(path)` helper using `Req.get(memories_url() <> path, headers: headers())` with the same status/error handling as `post/2`, and `defp post_crud(path, type, attrs)` helper that sends `{"data": {"type": type, "attributes": attrs}}` format. **VERIFIED response shapes via live API:** `create_thread` returns CRUD JSON:API envelope (`data.id`, `data.attributes.name`, `data.attributes.ended_at`); `add_message` returns flat map (`id`, `thread_id`, `role`, `content`, `episode_id`, `metadata`, `inserted_at`); `get_context` returns flat map (`context_text`, `facts`, `entities`, `episodes`, `citations`, `conversation_history`, `token_estimate`, `effective_query`); `end_thread` returns flat map (`id`, `ended_at`). Note: `create_thread` CRUD response needs unwrapping from the JSON:API `data.attributes` envelope. `done_when: "mix compile --warnings-as-errors"`
- [ ] 6.2.1.1 Add `@spec create_thread(String.t(), keyword()) :: {:ok, ThreadResult.t()} | {:error, term()}` and `def create_thread(name, opts \\ [])`. Uses the `post_crud/3` helper from 6.2.1.0: `post_crud("/api/threads", "thread", %{name: name, user_id: user_id_default()} |> maybe_put(:metadata, Keyword.get(opts, :metadata)))`. Note: `group_id` must NOT be in the body -- it is derived from the authenticated API key (tenant). The Thread `:create` action accepts `[:user_id, :name, :metadata]` only. `done_when: "mix compile --warnings-as-errors"`
- [ ] 6.2.1.2 Add `@spec add_thread_message(String.t(), String.t(), keyword()) :: {:ok, MessageResult.t()} | {:error, term()}` and `def add_thread_message(thread_id, content, opts \\ [])`. Body: `post("/api/threads/#{thread_id}/messages", %{content: content, role: Keyword.get(opts, :role, "assistant")} |> maybe_put(:metadata, Keyword.get(opts, :metadata)))`. Note: `thread_id` must NOT be in the body -- AshJsonApi extracts it from the URL path param `:thread_id` and maps it to the action argument automatically. Body should only contain `content`, `role`, and optionally `metadata`. The `:add_message` action accepts `role` as atom, one_of: `[:norole, :system, :assistant, :user, :function, :tool]`. The closest role for agent output is `:assistant`. `done_when: "mix compile --warnings-as-errors"`
- [ ] 6.2.1.3 Add `@spec thread_context(String.t(), keyword()) :: {:ok, ContextResult.t()} | {:error, term()}` and `def thread_context(thread_id, opts \\ [])`. This is a GET endpoint -- must NOT send a JSON body. Uses the `get/1` helper from 6.2.1.0. Action arguments are passed as URL query params: `get("/api/threads/#{thread_id}/context?#{URI.encode_query(Keyword.take(opts, [:query, :limit]))}")`. Note: the `:get_context` action accepts `thread_id` (from URL path), `query` (optional string), `limit` (integer, default 10), `history_limit` (integer, default 20), `template_id` (optional uuid). `done_when: "mix compile --warnings-as-errors"`
- [ ] 6.2.1.4 Add `@spec end_thread(String.t()) :: {:ok, ThreadResult.t()} | {:error, term()}` and `def end_thread(thread_id)`. Body: `post("/api/threads/#{thread_id}/end", %{})`. Note: `thread_id` comes from the URL path; the empty body wraps to `{"data": {}}` which is accepted since the `:end_thread` action has no body arguments. `done_when: "mix compile --warnings-as-errors"`

### 6.2.2 Thread Registry and GraphThread Resource

- [ ] **Task 6.2.2 Complete**
- **Governed by:** SWARM_MEMORY.md points 3, 15
- **Parent UCs:** —

Create an ETS-backed thread registry (pure functions, no GenServer) and a GraphThread Ash resource with 3 MCP actions for session thread management.

- [ ] 6.2.2.1 Create `lib/ichor/fleet/thread_registry.ex`. Define module `Ichor.Fleet.ThreadRegistry` with `@table :ichor_thread_registry`. Functions: `put(session_id, thread_id)` calls `:ets.insert(@table, {session_id, thread_id})`, `get(session_id)` calls `:ets.lookup(@table, session_id)` and returns `thread_id` or `nil`, `delete(session_id)` calls `:ets.delete(@table, session_id)`. No GenServer, no process -- pure ETS operations on a named public table. `done_when: "mix compile --warnings-as-errors"`
- [ ] 6.2.2.2 In `lib/ichor/application.ex`, in `start/2` before the `children` list, add: `if :ets.whereis(:ichor_thread_registry) == :undefined, do: :ets.new(:ichor_thread_registry, [:named_table, :public, :set])` `done_when: "mix compile --warnings-as-errors"`
- [ ] 6.2.2.3 Create `lib/ichor/agent_tools/graph_thread.ex` with `use Ash.Resource, domain: Ichor.AgentTools`. Add `action :start_thread, :map` with arguments: `session_id :string (allow_nil?: false)`, `task_description :string (allow_nil?: false)`. The `run/2` checks `ThreadRegistry.get(session_id)` -- if found, calls `MemoriesClient.thread_context(thread_id)` and returns existing context; if not found, calls `MemoriesClient.create_thread("ichor:#{session_id}", metadata: %{session_id: session_id})`, stores via `ThreadRegistry.put`, and returns thread_id. Description: "Start or resume a persistent thread for your session. Returns accumulated context from prior work." `done_when: "mix compile --warnings-as-errors"`
- [ ] 6.2.2.4 Add `action :write_outcome, :map` with arguments: `session_id :string (allow_nil?: false)`, `summary :string (allow_nil?: false)`, `decisions :string` (optional), `failures :string` (optional). The `run/2` looks up thread_id from ThreadRegistry, composes a structured message from summary+decisions+failures, calls `MemoriesClient.add_thread_message(thread_id, message)`, then calls `MemoriesClient.end_thread(thread_id)`, deletes from ThreadRegistry, and also calls `MemoriesClient.ingest(message, source: "agent", space: "project:ichor:fleet")` for fleet-wide discoverability. Description: "Write your session outcome and close the thread. Include decisions, failures, and recommendations for the next agent." `done_when: "mix compile --warnings-as-errors"`
- [ ] 6.2.2.5 Add `action :get_context, :map` with arguments: `session_id :string (allow_nil?: false)`, `query :string` (optional). The `run/2` looks up thread_id from ThreadRegistry, calls `MemoriesClient.thread_context(thread_id, query: query)`, returns the `context_text` field. Description: "Get accumulated context from your thread -- facts, entities, and episodes relevant to your mission." `done_when: "mix compile --warnings-as-errors"`
- [ ] 6.2.2.6 In `lib/ichor/agent_tools.ex`, add `GraphThread` to alias list and `resources do` block. Add 3 tools: `tool(:start_thread, GraphThread, :start_thread)`, `tool(:write_outcome, GraphThread, :write_outcome)`, `tool(:get_context, GraphThread, :get_context)` `done_when: "mix compile --warnings-as-errors"`

### 6.2.3 Thread Lifecycle Wiring

- [ ] **Task 6.2.3 Complete**
- **Governed by:** SWARM_MEMORY.md points 3, 13
- **Parent UCs:** —

Wire thread cleanup into AgentProcess terminate and update the instruction overlay with thread protocol instructions.

- [ ] 6.2.3.1 In `lib/ichor/fleet/agent_process.ex`, in `terminate/2`, after the existing `Ichor.EventBuffer.tombstone_session(state.id)` call, add a guarded async cleanup: `if Ichor.MemoriesBridge.enabled?() do Task.Supervisor.start_child(Ichor.TaskSupervisor, fn -> with thread_id when not is_nil(thread_id) <- Ichor.Fleet.ThreadRegistry.get(state.id) do Ichor.Archon.MemoriesClient.end_thread(thread_id); Ichor.Fleet.ThreadRegistry.delete(state.id) end end) end`. Add required aliases for MemoriesBridge, ThreadRegistry, MemoriesClient. `done_when: "mix compile --warnings-as-errors"`
- [ ] 6.2.3.2 In `lib/ichor/instruction_overlay.ex`, extend `graph_memory_section/1` to include thread instructions: "At session START: Call `start_thread` with your session_id and task description to get prior context. At session END: Call `write_outcome` with what you did, decisions made, failures, and recommendations before sending DONE." `done_when: "mix compile --warnings-as-errors"`

---

## 6.3 Role-Specific Memory Packets

- [ ] **Section 6.3 Complete**

Inject graph-retrieved context into agent instruction overlays at spawn time. No MCP tool needed -- this happens automatically before the agent starts working. Each role gets different search queries optimized for its needs. The packet builder is a pure function module with a 3-second timeout; spawn proceeds without a packet on failure.

### 6.3.1 MemoryPacket Builder Module

- [ ] **Task 6.3.1 Complete**
- **Governed by:** SWARM_MEMORY.md points 6, 11
- **Parent UCs:** —

Create a pure function module that builds role-specific memory packets by querying the Memories graph. No GenServer, no state. Each role gets different search queries: builders get recent decisions and failure patterns, leads get blockers and team history, reviewers get past gate failures, scouts get prior explorations. Uses `Task.yield/2` with 3-second timeout for HTTP calls.

- [ ] 6.3.1.1 Create `lib/ichor/fleet/memory_packet.ex`. Define `@spec build(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}` and `def build(session_id, capability, task_description)`. Dispatch to `defp build_for(capability, task_description)` via pattern match. Wrap the HTTP call in `Task.Supervisor.async_nolink(Ichor.TaskSupervisor, fn -> ... end)` with `Task.yield(task, 3_000) || Task.shutdown(task, :brutal_kill)`. Return `{:ok, ""}` on timeout or error. `done_when: "mix compile --warnings-as-errors"`
- [ ] 6.3.1.2 Implement `defp build_for("builder", task_desc)`: call `MemoriesClient.search(task_desc, scope: "edges", limit: 5)` and format results as "## Prior Knowledge\n\nRelevant facts from the knowledge graph:\n{formatted_facts}". Implement `defp build_for("lead", task_desc)`: search with scope "edges" for blockers + team history. Implement `defp build_for("reviewer", task_desc)`: search for gate failures and quality patterns. Implement `defp build_for(_, task_desc)`: generic facts search. All use the same `format_results/1` helper. Note: search operates across the full tenant graph -- there is no space filtering on the read path. `done_when: "mix compile --warnings-as-errors"`

### 6.3.2 Spawn-Time Packet Injection

- [ ] **Task 6.3.2 Complete**
- **Governed by:** SWARM_MEMORY.md point 10
- **Parent UCs:** —

Inject the memory packet into the agent's instruction overlay file after it's written but before the tmux session is created. Guarded by `MemoriesBridge.enabled?/0`. On failure, spawn proceeds without the packet.

- [ ] 6.3.2.1 In `lib/ichor/agent_spawner.ex`, in `spawn_local/1`, after the `InstructionOverlay.write_session_files(cwd, opts)` call succeeds and before `create_tmux_session/3`, add: `if Ichor.MemoriesBridge.enabled?() do case Ichor.Fleet.MemoryPacket.build(session_name, opts[:capability] || "builder", task_desc(opts[:task])) do {:ok, ""} -> :ok; {:ok, packet} -> overlay_path = Path.join(cwd, ".claude/ICHOR_OVERLAY.md"); File.write!(overlay_path, File.read!(overlay_path) <> "\n" <> packet); {:error, _} -> :ok end end`. Add a `defp task_desc(nil), do: ""` and `defp task_desc(task), do: task["subject"] || task[:subject] || ""` helper. `done_when: "mix compile --warnings-as-errors"`
