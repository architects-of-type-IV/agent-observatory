# ICHOR IV (formerly Observatory) - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents, part of Kardashev Type IV suite
- **Architect**: the user -- has authority over everything
- **Archon**: the Architect's agent interface. NOT a rename of Operator. Will be a real AI agent with tools + memory + LLM.
- **Operator**: current thin messaging relay (Architect -> agents). Will eventually be replaced by Archon.
- ADR-001: vendor-agnostic fleet control, ADR-002: ICHOR IV identity
- ADR-023/024/025: BEAM-native agent processes, team supervision, native messaging

## AgentRegistry Architecture (2026-03-09, DECOMPOSED)
- **AgentRegistry** (293 lines): thin GenServer, ETS ownership, message routing, client API
- **AgentEntry**: agent map constructor, shared utilities (uuid?, short_id, role_from_string)
- **EventHandler**: pure hook event -> agent state transformation (apply_event/2)
- **IdentityMerge**: CWD-based correlation of UUID-keyed (hook) and short-name-keyed (team) entries
- **TeamSync**: TeamWatcher data merge, uses IdentityMerge for canonical entry resolution
- **Sweep**: GC with ended_ttl (30min) and stale_ttl (1h), infrastructure session cleanup
- `derive_role/1` is a defdelegate to AgentEntry.role_from_string/1 (3 external callers)

## DashboardLive Dispatch Pattern (2026-03-09, OPTIMIZED)
- Each handler module exposes `dispatch/3` that matches event name + params, returns socket
- LiveView uses module attributes `@filter_events ~w(...)` + `when e in @events` guards
- **Three recompute tiers**: full recompute (data events), view-only recompute (display state), no recompute (pure UI toggles)
- **Debounced recompute**: PubSub events schedule recompute via Process.send_after (100ms coalesce window)
- **Deferred mount**: static render gets defaults, :load_data fires after WebSocket connects
- **Conditional computation**: analytics/timeline/feed/costs only computed when their view is active
- Template helpers still need explicit imports with `only:` lists in the LiveView

## Archon Architecture (2026-03-09)
- **Observatory.Archon** -- parent Ash domain (empty, for future conversation state / memory resources)
- **Observatory.Archon.Tools** -- AshAi subdomain with 10 tools across 5 resources
  - Tools.Agents, Tools.Teams, Tools.Messages, Tools.System, Tools.Memory
- **Archon.Chat**: stateless LLM conversation engine (LangChain + ChatAnthropic + AshAi)
  - `chat/2` -> `{:ok, response, history}`, history in LiveView assigns
  - Model: claude-sonnet-4-20250514, API key from env or config
- **Archon UI**: centered 16:9 translucent glass panel (key `a` or FAB)
  - Three tabs: Command (Q), Chat (W), Reference (E) -- keyboard-switchable
  - Command tab: 7 quick action cards (keys 1-7) + mini activity feed
  - Chat tab: full conversation view with Archon
  - Reference tab: all 10 shortcodes in clickable grid
  - `ArchonComponents` with sub-components (command_hud, chat_panel, reference_panel, etc.)
  - CSS: `archon-*` classes -- translucent glass (bg-black/40), amber glow, pulsing sigil
  - MutationObserver tracks `.archon-overlay` for keyboard context routing
  - System-role messages: amber alert bubble for HITL notifications
  - `DashboardArchonHandlers`: toggle, send, shortcode, async response handlers
  - Async dispatch via `Task.start` -> `handle_info({:archon_response, result})`
- Fleet tools are in-process calls; Memory tools call Memories HTTP API at localhost:4000
- Operator agent (role: :operator) excluded from NudgeEscalator stale detection
- **HITL notification**: pause/resume/approve/reject update paused_sessions immediately + inject system message into archon_messages + auto-open overlay

## Archon Memories Integration (2026-03-09)
- **MemoriesClient**: HTTP client using Req (search, ingest, query_memory)
- **Archon namespace**: group_id `0f8eae17-...`, user_id `8fe50fd6-...`
- Memories server must be running on port 4000
- **Space attribute**: hierarchical namespace string on all 3 resources (Episode, Entity, Fact)
  - Format: lowercase, colon-separated (`general`, `project:ichor`, `project:ichor:archon`)
  - Default: `"general"`. Propagated from episode through DigestEpisode to entities/facts.
  - SQL filter in VectorChord WHERE clauses, wired through full search pipeline.
- **Episode types (Zep-aligned)**: `type` = structural (`:text`, `:message`, `:json`), `source` = provenance (`:user`, `:agent`, `:system`, `:document`, `:api`)

## Fleet Layering (2026-03-09, COMPLETE)
- **Canonical API**: Fleet.Agent and Fleet.Team code interfaces for ALL reads and lifecycle ops
- **Fleet.Agent actions**: all, active, in_team, spawn, pause_agent, resume_agent, terminate_agent, launch, get_unread, mark_read, send_message, update_instructions
- **Fleet.Team actions**: all, alive, create_team, disband, spawn_member
- **Consistency rule**: all external callers route through Fleet code interfaces or Operator.send
- **Legacy modules ELIMINATED**: Mailbox, CommandQueue, TeamWatcher deleted. Zero references.
- **MailboxAdapter**: rewired to AgentProcess.send_message (was Mailbox ETS)
- **Operator.send fallback**: PubSub broadcast for dashboard visibility (was Mailbox)
- **LoadMessages**: hook events only (no Mailbox merge)
- **LoadTeams**: events + BEAM teams only (no TeamWatcher disk merge). Claude ~/.claude/teams/ deferred.

## AgentTools Domain (Refactored 2026-03-08)
- 6 focused resources: Inbox, Tasks, Memory, Recall, Archival, Agents
- MCP route only exposes 5 inbox tools
- Inbox now routes through Fleet.Agent code interfaces (get_unread, mark_read, send_message)

## Distribution Architecture (FOUNDATION COMPLETE)
- Fleet.HostRegistry: :pg groups (:observatory_agents scope), :net_kernel.monitor_nodes
- **:pg scope**: single scope `:observatory_agents` for all fleet groups. HostRegistry, AgentProcess, TeamSupervisor all use same scope. Child spec in application.ex must use explicit map (Erlang module).
- AgentSpawner: pattern-matched routing (local vs remote), ssh_tmux channel wiring
- AgentProcess: :pg join on init, lookup_cluster/1, list_cluster/0
- Delivery: ssh_tmux address format support alongside session+host format

## Memories Project (External, /Users/xander/code/www/memories)
- Zep/Graphiti-style knowledge graph with vector embeddings + BM25
- HTTP API: /api/episodes/ingest, /api/graph/search, /api/memories/query
- Docker: postgres (port 5434), falkordb (port 6379)
- NOT replacing MemoryStore yet -- only Archon gets Memories

## BEAM-Native Fleet Architecture
- **AgentProcess** GenServer: PID = identity, process mailbox = delivery
- **TeamSupervisor** DynamicSupervisor: one per team
- **FleetSupervisor** DynamicSupervisor: top-level
- **PubSub topics**: "fleet:lifecycle", "messages:stream"

## Event Pipeline
- **EventController**: thin HTTP adapter (~66 lines)
- **EventBuffer**: payload sanitization + tool duration tracking
- **Gateway.Router.ingest/1**: registry update + channel side effects

## Design Token System (2026-03-09, COMPLETE)
- **30+ `--ichor-*` tokens** in `assets/css/app.css`, two themes (ICHOR IV `:root` + Swiss `[data-theme="swiss"]`)
- **Tailwind v4 @theme**: `text-high/default/low/muted`, `bg-base/raised/highlight/surface/overlay`, `border-border/border-subtle`, `text-brand/success/error/info/interactive/violet/cyan` + bg/border variants
- **Archon CSS**: all `rgba()` -> `hsl(var(--ichor-*) / opacity)`. Panel radius uses `var(--ichor-radius-xl)`.
- **Workshop canvas**: 6 `--ichor-role-*` tokens (builder/scout/reviewer/lead/coordinator/default) with Swiss overrides
- **Zero hardcoded** zinc/amber/emerald/red/blue/indigo/hex across templates + CSS
- **~35 categorical colors** remain (yellow/orange/pink/rose/teal/lime/fuchsia/purple) for event-type visual identity
- **ichor-* component classes** (~50): `hsl(var(--ichor-*))` + `var(--ichor-radius-*)`. obs->ichor rename done.

## Elixir Code Guide (enforced)
- Pattern matching over if/else/cond/unless -- multi-head functions
- Aliases at top of module
- Focused modules: single responsibility, single purpose
- Zero warnings: `mix compile --warnings-as-errors`
- <=200 lines guideline (flexible when cohesive)

## User Preferences
- Minimal JavaScript -- "LiveView was made to limit JS usage"
- BEAM-native vision: supervisor, genserver, process with mailboxes
- No emoji. Execute directly, don't plan unless genuinely ambiguous.
- **Build modular**: components in components, small template files
- **DRY CSS**: Tailwind component classes (`@apply`) for theme portability
- **Ash-first**: use Ash Resources guide for handlers/actions/LiveViews
- **`.env` for secrets**: not auto-loaded, `source .env` before server start
