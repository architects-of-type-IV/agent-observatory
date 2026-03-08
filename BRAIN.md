# ICHOR IV (formerly Observatory) - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents, part of Kardashev Type IV suite
- **Architect**: the user -- has authority over everything
- **Archon**: ICHOR IV personified as top-level coordinator -- interprets Architect's will, drives fleet
- ADR-001: vendor-agnostic fleet control, ADR-002: ICHOR IV identity
- ADR-023/024/025: BEAM-native agent processes, team supervision, native messaging

## Workshop Domain (Ash + SQLite)
- **Domain**: `Observatory.Workshop` with 4 resources
- **TeamBlueprint**: parent resource, `manage_relationship(:direct_control)` on create/update for nested CRUD
- **AgentBlueprint**: `slot` (integer ID for canvas), `canvas_x`/`canvas_y`, `name`, `capability`, `model`, `permission`, `persona`, `file_scope`, `quality_gates`
- **SpawnLink**: `from_slot`/`to_slot` (integer agent slot refs)
- **CommRule**: `from_slot`/`to_slot`/`policy`/`via_slot`
- **Canvas <-> Ash mapping**: `id` <-> `slot`, `x/y` <-> `canvas_x/canvas_y`, `from/to` <-> `from_slot/to_slot`
- **Auto-save**: every canvas mutation calls `auto_save/1` which persists via `Ash.Changeset.for_create/update`
- **Event delegation**: DashboardLive has `def handle_event("ws_" <> _ = e, p, s)` that delegates to WorkshopHandlers
- **Preloading**: `list_blueprints/0` must call `Ash.load!(:agent_blueprints)` for agent count in UI
- **Migration**: `installed_extensions/0` must exist on Repo for `mix ash.gen.migration`

## BEAM-Native Fleet Architecture (Type IV Foundation)
- **AgentProcess** GenServer: PID = identity, process mailbox = delivery target
  - Registers in `Observatory.Fleet.ProcessRegistry` (Elixir.Registry, :unique)
  - Backend-pluggable: `state.backend` dispatches via `Delivery` module (pattern-matched heads)
  - Pause/resume: buffers messages when paused, delivers on resume
- **AgentProcess.Delivery**: Pure stateless module for message normalization + backend dispatch
- **TeamSupervisor** DynamicSupervisor: one per team, children are AgentProcesses
- **FleetSupervisor** DynamicSupervisor: top-level, holds teams + standalone agents
- **PubSub topics**: `"fleet:lifecycle"`, `"messages:stream"`

## Ash Domain Model
- **Fleet domain**: Agent + Team (DataLayer.Simple, read-only via preparations)
  - Gap: No write actions. Need generic actions delegating to GenServer layer
- **Activity domain**: Message + Task + Error (DataLayer.Simple, read-only)
- **Workshop domain**: TeamBlueprint + AgentBlueprint + SpawnLink + CommRule (SQLite)
- **AgentTools domain**: Inbox + Memory (generic actions for MCP)
- **Events domain**: Event + Session (SQLite)
- **Costs domain**: TokenUsage (SQLite)

## Elixir Style Guide (Enforced)
- Pattern matching on function heads, NOT if/else/cond
- `@doc`/`@spec` on publics, `@spec` on privates (no @doc)
- Modules <=200 lines, functions <=20 lines, args <=2-3
- Skip @doc on @impl callback functions

## Ash Struct Access (CRITICAL)
- **Ash resource structs do NOT support bracket access** `[:field]`
- Use dot access `struct.field` on Ash resources, bracket access on plain maps only

## Component Patterns
- Large components split: `.ex` (logic) + `.heex` (templates via `embed_templates`)
- Handler modules: imported via `import`, event prefix delegation (`"ws_" <>`)
- **Format-on-save race**: Edit tool fails when hooks modify file between Read and Edit

## User Preferences
- Zero warnings policy: `mix compile --warnings-as-errors`
- Minimal JavaScript -- "LiveView was made to limit JS usage"
- **BEAM-native vision**: supervisor, genserver, process with mailboxes as primitives
- **Canvas design freedom**: user wants to design canvas themselves, Ash models the data
- ADR-001 + ADR-002 = THE GOAL. Everything works toward sovereign fleet control.
