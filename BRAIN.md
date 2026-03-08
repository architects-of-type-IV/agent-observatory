# ICHOR IV (formerly Observatory) - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents, part of Kardashev Type IV suite
- **Architect**: the user -- has authority over everything
- **Archon**: the Architect's agent interface. NOT a rename of Operator. Will be a real AI agent with tools + memory + LLM.
- **Operator**: current thin messaging relay (Architect -> agents). Will eventually be replaced by Archon.
- ADR-001: vendor-agnostic fleet control, ADR-002: ICHOR IV identity
- ADR-023/024/025: BEAM-native agent processes, team supervision, native messaging

## Archon Architecture (2026-03-08)
- **Observatory.Archon** -- parent Ash domain (empty, for future conversation state / memory resources)
- **Observatory.Archon.Tools** -- AshAi subdomain with 7 tools across 4 resources
  - `Tools.Agents`: list_agents, agent_status (AgentRegistry queries)
  - `Tools.Teams`: list_teams (TeamWatcher queries)
  - `Tools.Messages`: recent_messages (Mailbox), send_message (Operator)
  - `Tools.System`: system_health (process liveness), tmux_sessions (Tmux + agent mapping)
- All tools are in-process calls, no HTTP overhead
- Operator agent (role: :operator) excluded from NudgeEscalator stale detection

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
- API.Client: backend-pluggable search (hybrid semantic + BM25, reranking, BFS biasing)
- HTTP API: /api/episodes/ingest, /api/graph/search, /api/graph/edges/:uuid, etc.
- Integration plan: Archon will call Memories HTTP API for knowledge graph queries
- NOT replacing MemoryStore yet -- only Archon gets Memories integration

## Architecture After Ash Refactor (2026-03-08)
- **DashboardState.recompute/1**: thin coordinator calling Ash code interfaces + Fleet.Queries + EventAnalysis
- **Fleet.Agent**: attributes include session_id, short_name, host, channels, last_event_at
- **LoadAgents preparation**: events -> teams -> disk -> tmux -> BEAM processes -> AgentRegistry merge -> sort
- **agent_index**: built from `Fleet.Agent.all!()` via `build_agent_lookup/1`
- **Fleet.Queries**: pure functions for active_sessions, inspector_events, topology
- **Activity.EventAnalysis**: tool_analytics, timeline, pair_tool_events

## Event Pipeline
- **EventController**: thin HTTP adapter (~66 lines)
- **EventBuffer**: payload sanitization + tool duration tracking
- **Costs.CostAggregator.record_usage/2**: async token usage recording
- **Gateway.Router.ingest/1**: registry update + channel side effects

## Workshop Architecture
- 4 handler modules: Handlers (canvas CRUD), Persistence (blueprint Ash ops), Presets (declarative configs), Types (AgentType CRUD)
- DashboardLive routing: specific event names first, `"ws_" <> _` catch-all last
- AgentType: Ash resource with sorted!() code interface, SQLite-backed

## BEAM-Native Fleet Architecture (Type IV Foundation)
- **AgentProcess** GenServer: PID = identity, process mailbox = delivery
- **TeamSupervisor** DynamicSupervisor: one per team
- **FleetSupervisor** DynamicSupervisor: top-level
- **PubSub topics**: "fleet:lifecycle", "messages:stream"

## Ash Domain Style
- Alias resources at top of domain module
- Short references in resources/tools blocks
- Resources focused and small (<200 lines)

## User Preferences
- Zero warnings policy: `mix compile --warnings-as-errors`
- Minimal JavaScript -- "LiveView was made to limit JS usage"
- BEAM-native vision: supervisor, genserver, process with mailboxes
- ADR-001 + ADR-002 = THE GOAL
