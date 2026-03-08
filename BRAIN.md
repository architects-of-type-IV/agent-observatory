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

## Gateway Registry Decomposition (2026-03-09, COMPLETE)
AgentRegistry was 894 lines. Now 669 lines after decomposition + dead code removal:

**Extracted modules:**
- `Gateway.OutputCapture` (108 lines) -- terminal output polling. Own GenServer in GatewaySupervisor.
- `Gateway.TmuxDiscovery` (115 lines) -- tmux session discovery + channel wiring. Own GenServer in GatewaySupervisor.

**Removed dead code:**
- Tree API: `children/1`, `parent/1`, `chain_of_command/1`, `reparent/2`, `add_child/2`, `remove_child/2`, `build_chain/2`
- `children: []` field from default_agent map

**Remaining in AgentRegistry (669 lines):**
- Event registration, team sync + identity merge, sweep/lifecycle, channel resolution, lookup helpers, BEAM process bridge
- Still over 200-line limit; team sync + identity merge (~130 lines) is the largest remaining extraction candidate

## Distribution Architecture (2026-03-09, FOUNDATION COMPLETE)
Multi-host agent fleet via BEAM clustering. Key design decisions:

**Supervision stays local** -- each node supervises its own AgentProcesses via local DynamicSupervisor.
**Discovery is global** -- `:pg` (OTP process groups) spans the BEAM cluster.
**Messaging works natively** -- `GenServer.call/cast(pid)` works across connected nodes (PIDs encode node ID).
**PubSub already distributed** -- `Phoenix.PubSub` broadcasts across connected nodes.

**New modules and APIs:**
- `Fleet.HostRegistry` GenServer (169 lines): tracks BEAM nodes, `:net_kernel.monitor_nodes/2`, `:pg` group `:observatory_hosts`
- `AgentProcess`: joins `:pg` group `{:agent, id}`. New: `lookup_cluster/1` (local-first, falls back to `:pg`), `list_cluster/0`
- `TeamSupervisor`: joins `:pg` group `{:team, name}`. New: `list_cluster/0`
- `FleetSupervisor.spawn_agent_on/2`: routes to local `spawn_agent/1` or remote via `:rpc.call`
- `AgentSpawner`: accepts `:host` option. `spawn_remote/2` calls target node's `spawn_local/1` via `:rpc`
- `:pg` scope `:observatory_agents` started in application supervisor
- `DNSCluster` already in supervision tree (set to `:ignore`), configure for production clustering

**Remaining gaps:**
- Clustering config (node naming, DNSCluster query)
- AgentRegistry ETS is node-local -- long-term: BEAM-native fleet via `:pg` replaces ETS
- Remote tmux delivery (SSH-based tmux commands for agents on remote hosts)
- AgentSpawner at 318 lines (over 200-line limit)

## Ash Domain Style
- Alias resources at top of domain module
- Short references in resources/tools blocks
- Resources focused and small (<200 lines)

## User Preferences
- Zero warnings policy: `mix compile --warnings-as-errors`
- Minimal JavaScript -- "LiveView was made to limit JS usage"
- BEAM-native vision: supervisor, genserver, process with mailboxes
- ADR-001 + ADR-002 = THE GOAL
