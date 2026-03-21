# Workshop Domain
Related: [Index](INDEX.md) | [Decisions](decisions.md) | [Factory Domain](factory-domain.md) | [Diagrams](../diagrams/architecture.md)

Workshop owns: team designs, canvas state, agent types, spawn compilation, prompt management.
Workshop does NOT own: prompt content for specific modes (binding yes, content no), AgentWatchdog (fleet concern), spawn mode dispatch.

---

## Ash Resources

### Team (`workshop_teams`)

The durable, authored team definition. Represents a reusable team configuration that can be launched against any project.

**Key fields**:
- `name` -- unique, used as the spawn key (`spawn("mes")` looks up `name: "mes"`)
- `strategy` -- OTP restart strategy (`one_for_one`, `rest_for_one`)
- `default_model` -- default Claude model for agents in this team
- `agents` -- JSON array of `AgentSlot` embedded resources (canvas positions, roles)
- `spawn_links` -- JSON array of `SpawnLink` (directed edges: agent B starts after A)
- `comm_rules` -- JSON array of `CommRule` (communication policies between agent slots)
- `prompt_module` -- **planned**: atom binding to a module implementing the prompt contract (AD-6)

**Actions** (need descriptions added per W1-7):
- `create` / `update` / `destroy` -- standard CRUD
- `spawn_team` -- compiles the design and launches agents in tmux. Entry point for UC2.
- `list_active` -- reads from Registry, not DB. Returns live fleet state.
- `disband` -- emits `:team_disband_requested` signal; Infrastructure subscriber terminates processes.

---

### TeamMember (`workshop_team_members`)

A concrete agent slot within a saved team. Carries the per-agent configuration used during TeamSpec compilation.

**Key fields**:
- `slot` -- integer slot number; maps to AgentSlot in the `agents` JSON column
- `name` -- agent name within the team (e.g., `"coordinator"`, `"worker-1"`)
- `capability` -- role category (`builder`, `reviewer`, `coordinator`, `lead`)
- `model` -- Claude model override for this agent
- `permission` -- Claude Code permission level (`default`, `bypass_permissions`)
- `extra_instructions` -- freeform text appended to the generated prompt
- `file_scope` -- which files/paths this agent can access
- `tool_scope` -- JSON list of allowed MCP tools
- `canvas_x`, `canvas_y` -- position on the Workshop canvas

---

### AgentType (`workshop_agent_types`)

A reusable agent archetype. TeamMember slots can reference an AgentType to inherit defaults.

**Key fields**:
- `name` -- unique archetype identifier (e.g., `"ash-elixir-expert"`, `"code-reviewer"`)
- `default_model`, `default_permission`, `default_persona`, `default_file_scope`
- `default_quality_gates` -- verification command (e.g., `"mix compile --warnings-as-errors"`)
- `default_tools` -- JSON list of MCP tools this agent type uses by default
- `color` -- canvas display color
- `sort_order` -- ordering in the agent type picker

---

## Embedded Resources (JSON Columns in Team)

### AgentSlot

Canvas-level agent configuration stored in the `workshop_teams.agents` JSON column.

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `id` | integer | required | Slot number, unique within team |
| `agent_type_id` | string | nil | Optional reference to AgentType archetype |
| `name` | string | required | Display name on canvas |
| `capability` | string | `"builder"` | Role category |
| `model` | string | `"sonnet"` | Claude model |
| `permission` | string | `"default"` | Claude Code permission level |
| `persona` | string | `""` | Short persona blurb; full prompts come from `prompt_module` |
| `file_scope` | string | `""` | File access constraint |
| `quality_gates` | string | `""` | Verification commands |
| `tools` | string[] | `[]` | MCP tool names |
| `x`, `y` | integer | `40`, `30` | Canvas position |

### SpawnLink

A directed dependency edge. Agent at slot `to` will not start until agent at slot `from` is ready.

| Field | Type | Notes |
|-------|------|-------|
| `from` | integer | Source slot |
| `to` | integer | Destination slot |

### CommRule

Communication policy between two agents. Controls which agents can message which.

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `from` | integer | required | Source slot |
| `to` | integer | required | Destination slot |
| `policy` | string | `"allow"` | `"allow"`, `"deny"`, `"via"` |
| `via` | integer | nil | Relay slot if `policy: "via"` |

**CommPolicy is new** (from Workshop agent): the `policy` and `via` fields implement the communication routing rules that the Bus uses to validate cross-agent messages. When `policy: "via"`, the Bus routes the message through the relay slot instead of directly.

---

## Canvas State

`Workshop.CanvasState` is a **pure data module** (not an Ash resource). It holds the in-progress editor state and provides transformation functions.

**Key functions**:
- `apply_team(canvas_state, team)` -- loads a saved Team into canvas state
- `add_agent(canvas_state, agent_slot)` -- adds an agent slot with canvas positioning
- `add_spawn_link(canvas_state, from_slot, to_slot)` -- adds a directed dependency edge
- `add_comm_rule(canvas_state, from_slot, to_slot, policy)` -- adds a communication rule
- `spawn_order(canvas_state)` -- topological sort of agents by spawn links

Canvas state is ephemeral: it exists in the LiveView socket assigns during editing. When the user saves, the canvas state is written to the Team Ash resource.

---

## TeamSpec Compilation (AD-3, AD-6)

### Current State (broken boundary)

`Workshop.TeamSpec.build(:mes | :pipeline | :planning)` puts caller knowledge inside the compiler:
- Three separate function heads with mode-specific private internals
- Imports `Factory.PlanningPrompts` directly into Workshop
- 395 lines handling mode dispatch that belongs to callers

### Target State

`Workshop.TeamSpec.compile(canvas_state, opts)` -- pure compilation:

```elixir
# Callers provide their own prompt strategy
Factory.Spawn.spawn(:pipeline, ctx) ->
  TeamSpec.compile(canvas_state, prompt_module: PipelinePrompts, context: ctx)

Factory.Spawn.spawn(:planning, ctx) ->
  TeamSpec.compile(canvas_state, prompt_module: PlanningPrompts, context: ctx)

Workshop.Spawn.spawn_team(name) ->
  TeamSpec.compile(canvas_state, prompt_module: team.prompt_module)
```

**Workshop.TeamSpec shrinks from 395 lines to ~150 lines** of pure team compilation logic. No mode knowledge. No Factory imports.

---

## Prompt Management

### Current Problem

The CRITICAL RULES block (communication protocol: `send_message`, `check_inbox`, `ANNOUNCE READY`) appears **verbatim in 11+ prompt functions** across three modules:
- `workshop/team_prompts.ex` (MES prompts)
- `workshop/pipeline_prompts.ex` (pipeline prompts)
- `factory/planning_prompts.ex` (planning prompts -- wrong home, should be Workshop)

### Target: Workshop.PromptProtocol

Extract shared protocol into a single module:

```elixir
defmodule Workshop.PromptProtocol do
  def critical_rules(tool_prefix), do: ...   # send_message, check_inbox, etc.
  def roster_block(session, names), do: ...
  def announce_ready(session_id), do: ...
end
```

Each prompt module composes from `PromptProtocol` functions + mode-specific content.

### Prompt Module Contract

Each team type's prompt module implements:

```elixir
@callback build_prompt(agent :: %AgentSlot{}, context :: map()) :: String.t()
```

The `prompt_module` field on the Team Ash resource binds the team to its prompt strategy. TeamSpec.compile calls `prompt_module.build_prompt/2` for each agent slot.

---

## Agent Types: Current vs. Target

### Current: 4 overlapping spawn actions on Agent resource

- `:spawn` -- programmatic spawn
- `:launch` -- human-initiated launch
- `:spawn_agent` -- variant with different args
- `:spawn_archon_agent` -- elevated spawn

Discovery cannot distinguish these. The opaque `:map` returns make them non-composable.

### Target: 2 typed actions

- `:spawn_agent` -- programmatic fleet spawn. Returns `%{session_id: String.t(), pid: pid()}`.
- `:launch_agent` -- human-initiated, with full UI context. Returns `%{session_id: String.t(), team_member_id: uuid()}`.

---

## Teams: Active vs. Designed

| | Designed Team (Workshop) | Active Team (Fleet) |
|---|---|---|
| **Ash resource** | `Team` in `workshop_teams` | Not a resource (ephemeral) |
| **Authority** | AshSqlite (durable) | Registry + AgentProcess (live) |
| **Lifetime** | Permanent | While team is running |
| **Query** | `Workshop.Team` Ash read actions | `Workshop.ActiveTeam` reads Registry |
| **Used for** | Design, editing, compilation | Monitoring, messaging, disbanding |

`Workshop.ActiveTeam` is a read-only action surface that queries the Registry -- it is NOT a persisted Ash resource. It provides the running team's member list, health, and session info.

---

## Spawn Convergence (UC2, UC3, UC4)

### Current: Two parallel spawn paths

| | Workshop.Spawn | Factory.Spawn |
|---|---|---|
| Entry | `spawn_team(name)` | `spawn(:pipeline\|:planning, opts)` |
| Spec builder | Inline `build_spec` + `build_preset_spec` | `TeamSpec.build/N` |
| Prompt source | `persona` field | TeamPrompts / PlanningPrompts |
| Session naming | `"workshop-SLUG"` | `"mes-ID"` / `"pipeline-ID"` |
| Launch | Signal round-trip via TeamSpawnHandler | Direct `TeamLaunch.launch` |
| Lifecycle | Fire-and-forget (no Runner) | Runner.start with monitoring |

### Target: One compile path

Both paths call `TeamSpec.compile(canvas_state, opts)`. Factory does its pre-spawn work (load tasks, validate DAG, group workers) then calls `spawn("pipeline")`. Workshop calls `spawn(team_name)` directly.

Pipeline pre-spawn steps (Loader, Validator, WorkerGroups) are **Factory concerns**, not spawn concerns. They remain in Factory, they just precede the `spawn/1` call instead of being wired inside it.

---

## Spawn Constraints (no new abstractions)

Spawn constraints are pattern matches in signal subscribers -- no "Policy" module needed:

1. `spawn/1` emits `:team_spawn_requested, %{team: "mes"}`
2. A subscriber pattern-matches on `team: "mes"` and checks if one is already running
3. If already running: ignore. If not: proceed with compile + launch.
4. Teams with no matching subscriber clause spawn freely.

The MesScheduler is the first example of a spawn policy subscriber.

---

## Data Flows

### UC1: Design a Team

```
Canvas UI -> Workshop.Team (Ash create/update)
          -> AgentSlot / SpawnLink / CommRule (embedded, updated via JSON)
          -> Saved as workshop_teams row
```

### UC2: Launch a Team

```
Canvas UI -> Workshop.Spawn.spawn_team(name)
          -> Workshop.Team.spawn_team action
          -> CanvasState.apply_team(team)
          -> TeamSpec.compile(canvas_state, prompt_module: team.prompt_module)
          -> emit :team_spawn_requested
          -> TeamSpawnHandler picks up signal
          -> Infrastructure.TeamLaunch.launch(spec)
          -> Scripts written, tmux created, agents registered in Fleet.Runtime
          -> emit :team_spawned
```

### UC2+: Factory-initiated spawn

```
Factory pre-spawn (Loader + Validator + WorkerGroups)
-> spawn("pipeline") with context
-> TeamSpec.compile(canvas_state, prompt_module: PipelinePrompts, context: ctx)
-> Infrastructure.TeamLaunch.launch(spec)
-> Projects.RunManager.start(:pipeline, opts)  <- Runner monitors lifecycle
```

---

## Build Sequence (implementation waves)

| Wave | Task | Notes |
|------|------|-------|
| W1-6 | Extract `Workshop.PromptProtocol` | Shared critical_rules/roster_block/announce_ready |
| W1-7 | Add action descriptions to Team, Agent, Floor | Discovery readiness |
| W3-1 | Add `prompt_module` field to Team/Preset | Schema migration via `mix ash.codegen` |
| W3-2 | Refactor TeamSpec.build/N -> compile/2 | Remove mode dispatch; accept opts |
| W3-3 | Workshop.Spawn delegates to TeamSpec.compile | One compilation path |
| W3-4 | Move PlanningPrompts to Workshop namespace | Fix wrong-home violation |
| W3-5 | Consolidate Agent's 4 spawn actions to 2 | typed returns for Discovery |
| W5-1 | Replace opaque :map returns with typed outputs | composable actions |
| W5-2 | Add Ash policies to Workshop | actor threading + authorization |
