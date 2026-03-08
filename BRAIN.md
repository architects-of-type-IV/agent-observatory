# ICHOR IV (formerly Observatory) - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents, part of Kardashev Type IV suite
- **Architect**: the user -- has authority over everything
- **Archon**: the Architect's agent interface. NOT a rename of Operator. Will be a real AI agent with tools + memory + LLM.
- **Operator**: current thin messaging relay (Architect -> agents). Will eventually be replaced by Archon.
- ADR-001: vendor-agnostic fleet control, ADR-002: ICHOR IV identity
- ADR-023/024/025: BEAM-native agent processes, team supervision, native messaging

## Archon Architecture (2026-03-09)
- **Observatory.Archon** -- parent Ash domain (empty, for future conversation state / memory resources)
- **Observatory.Archon.Tools** -- AshAi subdomain with 10 tools across 5 resources
  - `Tools.Agents`: list_agents, agent_status (AgentRegistry queries)
  - `Tools.Teams`: list_teams (TeamWatcher queries)
  - `Tools.Messages`: recent_messages (Mailbox), send_message (Operator)
  - `Tools.System`: system_health (process liveness), tmux_sessions (Tmux + agent mapping)
  - `Tools.Memory`: search_memory, remember, query_memory (Memories HTTP API)
- Fleet tools are in-process calls; Memory tools call Memories HTTP API at localhost:4000
- Operator agent (role: :operator) excluded from NudgeEscalator stale detection

## Archon Memories Integration (2026-03-09)
- **MemoriesClient** (`lib/observatory/archon/memories_client.ex`): HTTP client using Req
  - `search/2`: hybrid vector+BM25+graph search, returns hydrated facts/entities/episodes
  - `ingest/2`: fire-and-forget episode creation (async digestion extracts entities/facts)
  - `query_memory/2`: LLM-grounded Q&A with provenance
- **Archon namespace**: group_id `0f8eae17-15fc-5af1-8761-0093dc9b5027`, user_id `8fe50fd6-f0da-5adc-9251-6417dc3092e8`
- Memories server must be running on port 4000 for tools to work

## Memories Project Bugs Fixed (2026-03-09, in /Users/xander/code/www/memories)
- **Reranker dispatch**: `:rrf` shorthand atom used as module name. Added `@shorthand_to_module` in `API.Reranker`
- **SearchVector**: only searched `episodes` table. Now searches `episodes` + `graph_nodes` + `graph_edges`
- **Entity/Fact embeddings missing**: DigestEpisode pipeline didn't embed entities or facts. Added Step 4.5 (`EmbedEntities`) and Step 5.7 (`EmbedFacts`)
- **Result hydration**: `Client.Local` returned raw IDs+scores. Now loads full records from DB
- **group_id resolution**: `resolve_group_id/1` now prefers explicit `:group_id` over `user_id`
- **Server reload**: Reactor steps don't auto-reload in dev. Must restart server after code changes.

## AgentTools Domain (Refactored 2026-03-08)
- 6 focused resources replacing 2 bloated files (726 -> 498 lines)
- `Inbox`: check_inbox, acknowledge_message, send_message (agent message exchange)
- `Tasks`: get_tasks, update_task_status (TaskManager delegation)
- `Memory`: read_memory, memory_replace, memory_insert, memory_rethink (core Letta blocks)
- `Recall`: conversation_search, conversation_search_date (history queries)
- `Archival`: archival_memory_insert, archival_memory_search (long-term passages)
- `Agents`: create_agent, list_agents (MemoryStore agent management)
- MCP route only exposes 5 inbox tools. Memory tools are defined but unrouted.

## Memories Project (External, /Users/xander/code/www/memories)
- Zep/Graphiti-style knowledge graph with vector embeddings + BM25
- Core concepts: Episodes (raw memory), Entities (semantic nodes), Facts (temporal edges)
- HTTP API: /api/episodes/ingest, /api/graph/search, /api/graph/edges/:uuid, /api/memories/query
- Embedder: Ortex (local ONNX, s2 stack, 1024-dim multilingual-e5-base on /Volumes/T5/models/ONNX)
- Docker: postgres (port 5434, vchord-suite), falkordb (port 6379)
- Stale .md files -- don't trust docs, read source code
- NOT replacing MemoryStore yet -- only Archon gets Memories integration

## Architecture After Ash Refactor (2026-03-08)
- **DashboardState.recompute/1**: thin coordinator calling Ash code interfaces + Fleet.Queries + EventAnalysis
- **Fleet.Agent**: attributes include session_id, short_name, host, channels, last_event_at
- **Fleet.Queries**: pure functions for active_sessions, inspector_events, topology
- **Activity.EventAnalysis**: tool_analytics, timeline, pair_tool_events

## Event Pipeline
- **EventController**: thin HTTP adapter (~66 lines)
- **EventBuffer**: payload sanitization + tool duration tracking
- **Gateway.Router.ingest/1**: registry update + channel side effects

## Workshop Architecture
- 4 handler modules: Handlers, Persistence, Presets, Types
- AgentType: Ash resource with sorted!() code interface, SQLite-backed

## BEAM-Native Fleet Architecture (Type IV Foundation)
- **AgentProcess** GenServer: PID = identity, process mailbox = delivery
- **TeamSupervisor** DynamicSupervisor: one per team
- **FleetSupervisor** DynamicSupervisor: top-level
- **PubSub topics**: "fleet:lifecycle", "messages:stream"

## Gateway Registry Decomposition (2026-03-09, COMPLETE)
- AgentRegistry: 894 -> 669 lines. Extracted OutputCapture + TmuxDiscovery GenServers.
- Dead tree code removed (children/parent/chain_of_command/reparent)

## Distribution Architecture (FOUNDATION COMPLETE)
- Fleet.HostRegistry, :pg groups, FleetSupervisor.spawn_agent_on/2
- Gaps: clustering config, remote tmux delivery, AgentSpawner 318 lines

## Ash Domain Style
- Alias resources at top of domain module
- Short references in resources/tools blocks
- Resources focused and small (<200 lines)

## User Preferences
- Zero warnings policy: `mix compile --warnings-as-errors`
- Minimal JavaScript -- "LiveView was made to limit JS usage"
- BEAM-native vision: supervisor, genserver, process with mailboxes
- ADR-001 + ADR-002 = THE GOAL
