# ICHOR IV (formerly Observatory) - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents, part of Kardashev Type IV suite
- **Architect**: the user -- has authority over everything
- **Archon**: the Architect's agent interface. NOT a rename of Operator. Will be a real AI agent with tools + memory + LLM.
- **Operator**: current thin messaging relay (Architect -> agents). Will eventually be replaced by Archon.
- ADR-001: vendor-agnostic fleet control, ADR-002: ICHOR IV identity

## Agent Identity Architecture (2026-03-10, CRITICAL LESSON)
- **tmux session name IS the canonical session_id** for agents running in tmux. EventBuffer.resolve_session_id uses it unconditionally -- no BEAM process alive check (was a race condition).
- **Agent name is NEVER Path.basename(cwd)**. Project dir goes in `:project` field. Name comes from: tmux session name > short UUID.
- **`AgentEntry.short_id/1`** is the SINGLE source for display abbreviation. Uses `uuid?/1` (binary pattern match, zero allocation) to detect UUIDs. UUIDs -> 8 chars. Human names -> pass through.
- **Don't filter, fix implementation**: `infrastructure_session?` filtering masks bugs. Only "obs" (tmux server) and numeric-only sessions are infrastructure. "ichor-" prefixed sessions are real agents.
- **BEAM is god**: every non-infrastructure tmux session MUST have a supervised AgentProcess. TmuxDiscovery enforces this continuously (5s poll), not just at startup.

## Subagent Architecture (2026-03-09)
- **Subagents are metadata on the parent**: they share the parent's session_id, don't create separate Fleet.Agent entries
- **Data source**: PreToolUse "Agent"/"Task" events have rich `tool_input` (description, subagent_type, name)
- **Pairing**: PreToolUse + PostToolUse matched by `tool_use_id`. Active = no PostToolUse yet.

## Agent Lifecycle (2026-03-10)
- **Single cleanup point**: `AgentProcess.terminate/2` handles cleanup (tmux kill, AgentRegistry remove, tombstone, PubSub broadcast)
- **Shutdown preserves events**: terminate calls `tombstone_session` not `remove_session`. Agent stays visible in sidebar as ended. Only MCP `stop_agent` fully purges.
- **Tombstones**: 30s ETS marker. Events resolving to tombstoned session are dropped (prevents SessionEnd ghost after tmux kill).
- **Session aliases**: EventBuffer caches UUID->tmux_session in ETS. Late events with only UUID resolve via alias.
- **Ghost detection**: no events AND no tmux AND status :ended/:unknown. Uses `:status` field from LoadAgents, NOT per-agent Registry lookups in templates.
- **AgentMonitor crash detection**: checks actual liveness (BEAM process alive OR tmux session exists) before declaring crash. Idle != crashed.
- **No idle filtering**: sidebar shows ALL sessions. Idle sessions sorted to bottom, never hidden.

## LoadAgents Pipeline Order (2026-03-10)
events -> teams -> disk members -> **BEAM processes** -> tmux-only -> registry merge -> subagents -> sort

BEAM processes BEFORE tmux-only so that tmux_session field from BEAM metadata enables dedup.

## NudgeEscalator (2026-03-09)
- 4-level escalation: warn (0) -> tmux nudge (1) -> HITL pause (2) -> zombie (3)
- Non-tmux agents capped at level 0. Auto-unpause on activity. Thresholds: 600s/300s.

## DashboardLive Dispatch Pattern
- Each handler module exposes `dispatch/3`, LiveView uses `when e in @events` guards
- Three recompute tiers: full (data), view-only (display), none (UI toggles)
- Debounced 100ms coalesce via Process.send_after

## MCP Tool Pattern (AshAi)
- Resource with `use Ash.Resource, domain: Ichor.AgentTools`
- Generic `action :name, :map do ... run fn ... end`
- **Naming**: avoid Ash reserved words for arguments (e.g., `prompt` not `task`)

## Archon Architecture (2026-03-09)
- `Archon.Tools` subdomain (10 tools, 5 resources), `Archon.Chat` (LangChain + AshAi)
- Fleet tools in-process; Memory tools HTTP localhost:4000 via MemoriesClient

## BEAM-Native Fleet Architecture
- **AgentProcess** GenServer: PID = identity, process mailbox = delivery
- **TeamSupervisor** DynamicSupervisor: one per team
- **FleetSupervisor** DynamicSupervisor: top-level
- **PubSub topics**: "fleet:lifecycle", "messages:stream"

## Design Token System (COMPLETE)
- 30+ `--ichor-*` tokens, two themes (ICHOR IV + Swiss)
- Archon CSS NOT yet tokenized (hardcoded rgba)

## User Preferences (ENFORCED)
- **"We dont filter. We fix implementation so filtering out is not needed."**
- **"BEAM is god"** -- every agent tmux session must have a BEAM AgentProcess
- Minimal JavaScript. BEAM-native vision. No emoji. Execute directly.
- Build modular. DRY CSS. Ash-first. `.env` for secrets.
