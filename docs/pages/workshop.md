Let me systematically find all workshop-related files.
Now let me check the Ash resources and the dashboard_live.ex for how workshop is mounted:
I now have a complete picture of the Workshop page. Here is the full feature breakdown:

---

# Workshop Page - Complete Feature Analysis

The Workshop is a tab within the main `DashboardLive` LiveView, activated via the URL param `?view=workshop`. It is a visual team builder for composing, saving, and launching multi-agent Claude teams.

---

## Layout

The page is split into two columns:

- Left: full-height interactive canvas with a presets bar across the top
- Right: 320px fixed sidebar with stacked configuration and management panels

---

## Presets Bar (top of canvas)

Data source: `Ichor.Control.Presets.ui_list/0` -- compiled from a compile-time map, no database involved.

Available presets (rendered as colored pill buttons):

| Name | Label | Color | Team Structure |
|---|---|---|---|
| `dag` | DAG Pipeline | cyan | coordinator (opus) + lead (sonnet), bidirectional allow rules |
| `genesis_a` | Genesis Mode A | violet | coordinator + architect + reviewer, coordinator mediates |
| `genesis_b` | Genesis Mode B | violet | coordinator + analyst + designer |
| `genesis_c` | Genesis Mode C | violet | coordinator + planner + architect |
| `mes` | MES Factory | warning | coordinator + lead + planner + 2 scouts |
| `research` | Research Squad | violet | coordinator (opus) + 3 scouts (haiku/sonnet), one_for_all |
| `review` | Review Chain | brand | architect (lead) + reviewer + builder + scout, rest_for_one, includes a `route` and `deny` comm rule |
| `solo` | Solo Builder | success | single builder agent (opus) |

Clicking a preset: clears the canvas, populates it with the preset's full agent/link/rule graph, and auto-saves as a new blueprint. Each preset carries preset team name, strategy, default model, canvas positions, spawn links, and comm rules.

Clear button: destroys the current blueprint record from the database, resets all canvas state to defaults.

---

## Canvas Area

UI element: a `<div>` with `phx-hook="WorkshopCanvas"` and `phx-update="ignore"` (rendered entirely by the JS hook, not LiveView re-renders).

Background: dot-grid pattern using CSS radial-gradient.

### Agent Nodes

Each node is a draggable `<div>` absolutely positioned on the canvas. Rendered entirely by the JS hook from `ws_state` push events.

Node anatomy:
- Colored dot + agent name + capability badge (abbreviation: BLD/SCT/REV/LEAD/COORD)
- Body: `model`, `permission`, truncated `persona` (first 30 chars)
- Two ports at the bottom:
  - Green "spawn" port (left): drag to another agent to set spawn-child relationship
  - Cyan "comm" port (right): drag to another agent to add a communication rule

Clicking a node (not on a port): fires `ws_select_agent`, highlights the node with a `selected` class, and populates the right panel Agent Configuration form.

Dragging a node body: live-updates position client-side during drag; fires `ws_move_agent` on mouseup, which persists coordinates to the server and triggers an auto-save.

Empty state message: "Click '+ Agent' or use a preset to start" with sub-hint about green/cyan ports.

### SVG Connection Lines

Rendered inside an overlay `<svg class="ws-lines">` by the JS hook. Three types of connections are drawn as cubic bezier paths with arrowhead markers:

- Spawn links: solid emerald green lines from spawn port to top of target node
- Comm rules (allow): dashed cyan lines
- Comm rules (deny): dashed red lines
- Comm rules (route): dashed violet lines; if a `via` agent is specified, draws a two-segment path through the intermediary agent
- Temporary drag preview line: dashed line following cursor during port drag

### Canvas Toolbar (above canvas)

- Title: "Team Builder"
- Agent-add buttons: if AgentTypes are defined in the database, one button per type (color-coded dot + "+ {name}"). If no types exist, a generic "+ Agent" button.
- Stats readout: agent count, spawn link count, comm rule count

---

## Right Sidebar Panels

### 1. Team Configuration

Form (`phx-change="ws_update_team"`, debounced):

- Team Name (text input, debounce 300ms) -- stored as `ws_team_name`
- Strategy (select): `one_for_one`, `rest_for_one`, `one_for_all` -- OTP supervisor strategy
- Default Model (select): `sonnet`, `opus`, `haiku`
- Project / CWD (monospace text input, debounce 300ms) -- used as working directory when launching; falls back to `File.cwd!()` if blank

### 2. Agent Configuration (conditional, shown when an agent is selected)

Form (`phx-change="ws_update_agent"`, all fields debounced):

- Name (text, debounce 300ms)
- Capability (select): `builder`, `scout`, `reviewer`, `lead`, `coordinator`
- Model (select): `sonnet`, `opus`, `haiku`
- Permission Mode (select): `default`, `plan`, `dangerously_skip`
- Persona / System Prompt (textarea, 3 rows, debounce 500ms)
- File Scope (monospace textarea, 2 rows, debounce 500ms) -- one path per line
- Quality Gates (monospace textarea, 2 rows, debounce 500ms) -- one command per line, default `mix compile --warnings-as-errors`
- Remove Agent button (full-width danger button): removes the selected agent and all its spawn links and comm rules

### 3. Spawn Hierarchy

Read-only tree view built server-side by `WorkshopComponents.spawn_tree_html/2`. Shows agents in depth-first order with indentation levels and connecting `⌞` glyphs. Each non-root node has a hover-reveal `x` button that fires `ws_remove_spawn_link` with the link's index.

Empty states: "No agents yet" or "Draw spawn links to build hierarchy".

### 4. Communication Rules

List of all comm rules. Each rule shows:
- Policy badge (colored by policy: allow=green, deny=red, route=violet)
- from agent name -> to agent name
- optional "via {agent name}" for route rules
- `x` remove button (fires `ws_remove_comm_rule` with index)

When dragging a comm port and dropping on a target, the new rule always defaults to policy `"allow"`. There is no UI to create deny/route rules interactively -- those can only come from presets or direct blueprint editing.

### 5. Saved Blueprints

Data source: `Ichor.Control.Blueprint` Ash resource, SQLite table `workshop_blueprints`. Listed sorted by `inserted_at desc`.

- "New" button (shown when a blueprint is loaded): fires `ws_new_blueprint`, clears canvas and unsets `ws_blueprint_id`
- "Save" / "Update" button (shown when agents exist): fires `ws_save_blueprint`, triggers auto-save and refreshes the list
- Blueprint list items:
  - Blueprint name (truncated) + agent count
  - Hover-reveal "load" button: fires `ws_load_blueprint`, deserializes the stored JSON back to canvas state and pushes to JS
  - Hover-reveal "del" button: fires `ws_delete_blueprint` with a browser `data-confirm` dialog; if the deleted blueprint is currently loaded, also clears the canvas

Active blueprint highlighted with cyan background ring. Auto-save is triggered on every significant action (add, move, update, remove, link).

Blueprint persistence format: agents stored as `{:array, :map}` with string-keyed JSON maps including `slot`, `name`, `capability`, `model`, `permission`, `persona`, `file_scope`, `quality_gates`, `canvas_x`, `canvas_y`. Spawn links stored as `{from_slot, to_slot}`. Comm rules stored as `{from_slot, to_slot, policy, via_slot}`.

### 6. Agent Types

Data source: `Ichor.Control.AgentType` Ash resource, SQLite table `workshop_agent_types`, sorted by `sort_order asc, name asc`.

Agent types are reusable archetypes that pre-fill agent fields when stamped onto the canvas.

Fields per type: `name`, `capability`, `default_model`, `default_permission`, `default_persona`, `default_file_scope`, `default_quality_gates`, `color` (optional hex), `sort_order`.

Agent type list: shows capability dot color + name + capability badge + default model. Hover reveals "edit" and "del" (with confirm dialog) buttons.

"+ New Type" button: shows an inline create form.

Inline create/edit form (below the list):
- Name (required text input)
- Capability (select: builder/scout/reviewer/lead/coordinator)
- Model (select: sonnet/opus/haiku)
- Permission (select: default/plan/dangerously_skip)
- Persona (textarea, debounce 500ms)
- File Scope (monospace textarea, debounce 500ms)
- Quality Gates (monospace textarea, debounce 500ms)
- "Create" / "Save" + "Cancel" buttons

Saving a type refreshes `ws_agent_types` assign and collapses the form. If the type being edited is deleted while the form is open, the form is also closed.

### 7. Launch Team

Shown only when the canvas has at least one agent. Single full-width "Launch Team" button with a browser confirm dialog showing team name and agent count.

On confirm: fires `ws_launch_team`, which:
1. Calls `TeamSpecBuilder.build_from_state/1` to construct a `TeamSpec`
2. Agents are sorted in depth-first spawn order via `Presets.spawn_order/2`
3. Each agent gets a prompt assembled from: identity line, persona, permission, file scope, quality gates, spawn responsibilities list, comm rules list
4. Session name derived as `workshop-{slugified-team-name}`
5. Window names derived as `{id}-{name}` slugified
6. CWD defaults to `File.cwd!()` if blank
7. Passes the spec to `TeamLaunch.launch/1`
8. Shows flash: "Team {name} launched with N/N agents" or error flash on failure

---

## State Management

All workshop state lives as socket assigns with the `ws_` prefix:

- `ws_agents` - list of agent maps with id, name, capability, model, permission, persona, file_scope, quality_gates, x, y
- `ws_spawn_links` - list of `%{from: id, to: id}` maps
- `ws_comm_rules` - list of `%{from: id, to: id, policy: string, via: id|nil}` maps
- `ws_selected_agent` - integer id or nil
- `ws_next_id` - monotonic integer for next agent slot
- `ws_team_name` - string, default "alpha"
- `ws_strategy` - string, default "one_for_one"
- `ws_default_model` - string, default "sonnet"
- `ws_cwd` - string, default ""
- `ws_blueprint_id` - UUID string or nil (tracks current persisted blueprint)
- `ws_blueprints` - list of `Blueprint` records from database
- `ws_agent_types` - list of `AgentType` records from database
- `ws_editing_type` - `AgentType` record, `:new`, or `nil`

The JS hook receives state via `push_event(socket, "ws_state", ...)` and is the sole renderer of agent nodes and SVG lines. The hook pushes events back to LiveView for all mutations.

---

## Key Files

- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/workshop_components/workshop_view.html.heex` - full page template
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/workshop_components.ex` - component module, cap color helpers, spawn tree builder
- `/Users/xander/code/www/kardashev/observatory/assets/js/hooks/workshop_canvas.js` - JS hook: node rendering, drag, port drag, SVG lines
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_workshop_handlers.ex` - canvas event handlers (add/select/move/update/remove agents, links, rules, preset, clear, launch)
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/workshop_persistence.ex` - blueprint CRUD event handlers and auto-save logic
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/workshop_types.ex` - AgentType CRUD event handlers
- `/Users/xander/code/www/kardashev/observatory/lib/ichor/control/blueprint_state.ex` - pure state transition functions for all canvas operations
- `/Users/xander/code/www/kardashev/observatory/lib/ichor/control/presets.ex` - all 8 built-in presets plus spawn-order sorting
- `/Users/xander/code/www/kardashev/observatory/lib/ichor/control/blueprint.ex` - Ash resource, SQLite persistence
- `/Users/xander/code/www/kardashev/observatory/lib/ichor/control/agent_type.ex` - Ash resource, SQLite persistence
- `/Users/xander/code/www/kardashev/observatory/lib/ichor/control/team_spec_builder.ex` - builds `TeamSpec` from workshop state for launch
