# ICHOR IV (formerly Observatory) - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents, part of Kardashev Type IV suite
- **Architect**: the user -- has authority over everything
- **Archon**: the Architect's agent interface. NOT a rename of Operator. Will be a real AI agent with tools + memory + LLM.
- **Operator**: current thin messaging relay (Architect -> agents). Will eventually be replaced by Archon.
- ADR-001: vendor-agnostic fleet control, ADR-002: ICHOR IV identity
- ADR-023/024/025: BEAM-native agent processes, team supervision, native messaging

## Subagent Architecture (2026-03-09)
- **Subagents are metadata on the parent**: they share the parent's session_id, don't create separate Fleet.Agent entries
- **Data source**: PreToolUse "Agent"/"Task" events have rich `tool_input` (description, subagent_type, name). SubagentStart events have nil subagent_id and no useful metadata.
- **Pairing**: PreToolUse + PostToolUse matched by `tool_use_id`. Active = no PostToolUse yet.
- **Fleet.Agent.subagents**: `{:array, :map}` attribute, populated by LoadAgents.build_subagent_map
- **UI**: clickable rows dispatch `select_subagent` event, detail panel shows type/parent/description

## Agent Lifecycle (2026-03-09, CLOSED-LOOP)
- **Single cleanup point**: `AgentProcess.terminate/2` handles ALL cleanup (tmux kill, AgentRegistry remove, EventBuffer purge, PubSub broadcast)
- **SessionEnd** hook terminates the BEAM process (which triggers terminate/2 cascade)
- **Sweep** does full sweep: terminate process + kill tmux + clean eventbuffer + delete ETS. Also catches orphan BEAM processes.
- **Ghost detection**: agents with `event_count == 0` in the fleet UI get a GHOST badge
- **Infrastructure filter**: `TmuxDiscovery.infrastructure_session?/1` filters `obs`, `obs-*`, numeric-only sessions

## NudgeEscalator (2026-03-09)
- 4-level escalation: warn (0) -> tmux nudge (1) -> HITL pause (2) -> zombie (3)
- **Non-tmux agents**: capped at level 0 (no tmux nudge or HITL pause possible)
- **Auto-unpause**: new events from a session with level >= 2 trigger HITLRelay.unpause + escalation reset
- **Thresholds**: stale 600s, nudge interval 300s
- Operator agent excluded from stale detection

## AgentRegistry Architecture (2026-03-09, DECOMPOSED)
- **AgentRegistry** (293 lines): thin GenServer, ETS ownership, message routing, client API
- **AgentEntry**: agent map constructor, shared utilities (uuid?, short_id, role_from_string)
- **EventHandler**: pure hook event -> agent state transformation (apply_event/2)
- **IdentityMerge**: CWD-based correlation of UUID-keyed (hook) and short-name-keyed (team) entries
- **TeamSync**: TeamWatcher data merge, uses IdentityMerge for canonical entry resolution
- **Sweep**: full GC -- terminates BEAM processes, kills tmux, purges events, deletes ETS entries
- `derive_role/1` is a defdelegate to AgentEntry.role_from_string/1 (3 external callers)

## DashboardLive Dispatch Pattern (2026-03-09, OPTIMIZED)
- Each handler module exposes `dispatch/3` that matches event name + params, returns socket
- LiveView uses module attributes `@filter_events ~w(...)` + `when e in @events` guards
- **Three recompute tiers**: full recompute (data events), view-only recompute (display state), no recompute (pure UI toggles)
- **Debounced recompute**: PubSub events schedule recompute via Process.send_after (100ms coalesce window)
- **Deferred mount**: static render gets defaults, :load_data fires after WebSocket connects
- **Conditional computation**: analytics/timeline/feed/costs only computed when their view is active

## MCP Tool Pattern (AshAi)
- Resource with `use Ash.Resource, domain: Ichor.AgentTools`
- Generic `action :name, :map do ... run fn ... end`
- Registered in domain's `tools do` block
- Whitelisted in router's `forward "/mcp"` tools list
- **Naming**: avoid Ash reserved words for arguments (e.g., `prompt` not `task`)

## Archon Architecture (2026-03-09)
- **Ichor.Archon** -- parent Ash domain
- **Ichor.Archon.Tools** -- AshAi subdomain with 10 tools across 5 resources
- **Archon.Chat**: stateless LLM conversation engine (LangChain + ChatAnthropic + AshAi)
- **Archon UI**: centered 16:9 translucent glass panel (key `a` or FAB), 3 tabs (Command/Chat/Reference)
- Fleet tools in-process; Memory tools HTTP localhost:4000 via MemoriesClient

## AgentTools Domain (Refactored 2026-03-08)
- 7 resources: Inbox, Tasks, Memory, Recall, Archival, Agents, Spawn
- MCP exposes: check_inbox, acknowledge_message, send_message, get_tasks, update_task_status, spawn_agent, stop_agent
- Spawn delegates to AgentSpawner for tmux session creation + BEAM process registration

## Fleet Layering (2026-03-09, COMPLETE)
- **Canonical API**: Fleet.Agent and Fleet.Team code interfaces for ALL reads and lifecycle ops
- **Legacy ELIMINATED**: Mailbox, CommandQueue, TeamWatcher deleted. Zero references.
- **MailboxAdapter**: rewired to AgentProcess.send_message

## Distribution Architecture (FOUNDATION COMPLETE)
- Fleet.HostRegistry: :pg groups (:ichor_agents scope), :net_kernel.monitor_nodes
- AgentSpawner: pattern-matched routing (local vs remote), ssh_tmux channel wiring
- Remaining: clustering config (DNSCluster env var), remote tmux delivery (SSH)

## BEAM-Native Fleet Architecture
- **AgentProcess** GenServer: PID = identity, process mailbox = delivery
- **TeamSupervisor** DynamicSupervisor: one per team
- **FleetSupervisor** DynamicSupervisor: top-level
- **PubSub topics**: "fleet:lifecycle", "messages:stream"

## Design Token System (2026-03-09, COMPLETE)
- 30+ `--ichor-*` tokens, two themes (ICHOR IV + Swiss)
- Zero hardcoded zinc/amber/emerald/red/blue/indigo/hex across templates + CSS
- Archon CSS NOT yet tokenized (hardcoded rgba)

## Elixir Code Guide (enforced)
- Pattern matching over if/else/cond/unless
- Aliases at top. Focused modules. Zero warnings. <=200 lines guideline.

## User Preferences
- Minimal JavaScript. BEAM-native vision. No emoji. Execute directly.
- Build modular. DRY CSS. Ash-first. `.env` for secrets.
