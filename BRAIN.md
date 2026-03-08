# ICHOR IV (formerly Observatory) - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents, part of Kardashev Type IV suite
- **Architect**: the user -- has authority over everything
- **Archon**: ICHOR IV personified as top-level coordinator -- interprets Architect's will, drives fleet
- ADR-001: vendor-agnostic fleet control, ADR-002: ICHOR IV identity
- ADR-023/024/025: BEAM-native agent processes, team supervision, native messaging

## Architecture After Ash Refactor (2026-03-08)
- **DashboardState.recompute/1**: thin coordinator calling Ash code interfaces + Fleet.Queries + EventAnalysis
- **Fleet.Agent**: attributes now include session_id, short_name, host, channels, last_event_at
- **LoadAgents preparation**: events -> teams -> disk -> tmux -> BEAM processes -> AgentRegistry merge -> sort
- **agent_index**: built from `Fleet.Agent.all!()` via `build_agent_lookup/1` (converts structs to maps for bracket access)
- **AgentRegistry.derive_role/1**: canonical role classification (public), delegates from FleetHelpers + DashboardTeamHelpers
- **Fleet.Queries**: pure functions for active_sessions, inspector_events, topology
- **Activity.EventAnalysis**: tool_analytics, timeline, pair_tool_events (shared Pre/Post pairing)
- **Template assigns**: paused_sessions + mailbox_messages populated in recompute, not in heex

## Event Pipeline (After Phase 6 Extraction)
- **EventController**: thin HTTP adapter (~66 lines). extract_envelope -> attrs -> EventBuffer.ingest -> Costs -> PubSub -> Router.ingest
- **EventBuffer**: owns payload sanitization (strip tool_response, truncate tool_input >500 chars) + tool duration tracking (ETS @tool_start_table, Pre/Post matching)
- **Costs.CostAggregator.record_usage/2**: async token usage recording with per-model cost estimation
- **Gateway.Router.ingest/1**: registry update + channel side effects (SessionStart -> create channel, PreToolUse -> TeamCreate/Delete/SendMessage intercepts)

## Workshop Domain (Ash + SQLite)
- **Domain**: `Observatory.Workshop` with 4 resources
- **TeamBlueprint**: parent resource, `manage_relationship(:direct_control)` on create/update for nested CRUD
- **Canvas <-> Ash mapping**: `id` <-> `slot`, `x/y` <-> `canvas_x/canvas_y`, `from/to` <-> `from_slot/to_slot`
- **Auto-save**: every canvas mutation calls `auto_save/1` which persists via `Ash.Changeset.for_create/update`
- **Preloading**: `list_blueprints/0` must call `Ash.load!(:agent_blueprints)` for agent count in UI

## BEAM-Native Fleet Architecture (Type IV Foundation)
- **AgentProcess** GenServer: PID = identity, process mailbox = delivery target
  - Registers in `Observatory.Fleet.ProcessRegistry` (Elixir.Registry, :unique)
  - Backend-pluggable: `state.backend` dispatches via `Delivery` module (pattern-matched heads)
- **TeamSupervisor** DynamicSupervisor: one per team, children are AgentProcesses
- **FleetSupervisor** DynamicSupervisor: top-level, holds teams + standalone agents
- **PubSub topics**: `"fleet:lifecycle"`, `"messages:stream"`

## Ash Domain Model
- **Fleet domain**: Agent + Team (DataLayer.Simple, read-only via preparations)
- **Activity domain**: Message + Task + Error (DataLayer.Simple) + EventAnalysis (plain module)
- **Workshop domain**: TeamBlueprint + AgentBlueprint + SpawnLink + CommRule (SQLite)
- **AgentTools domain**: Inbox + Memory (generic actions for MCP)
- **Events domain**: Event + Session (SQLite)
- **Costs domain**: TokenUsage (SQLite)

## Elixir Style Guide (Enforced)
- Pattern matching on function heads, NOT if/else/cond
- `@doc`/`@spec` on publics, `@spec` on privates (no @doc)
- Modules <=200 lines, functions <=20 lines, args <=2-3

## Ash Struct Access (CRITICAL)
- **Ash resource structs do NOT support bracket access** `[:field]`
- Use dot access `struct.field` on Ash resources, bracket access on plain maps only
- **agent_index** maps are plain maps (Map.from_struct), so bracket access works there

## User Preferences
- Zero warnings policy: `mix compile --warnings-as-errors`
- Minimal JavaScript -- "LiveView was made to limit JS usage"
- **BEAM-native vision**: supervisor, genserver, process with mailboxes as primitives
- ADR-001 + ADR-002 = THE GOAL. Everything works toward sovereign fleet control.
