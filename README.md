# workshop_canvas

Pure state transitions for a visual agent-team designer.

Extracted from the ICHOR IV agent observatory, where a drag-and-drop canvas let
you place agents, wire up who spawns whom, declare who may talk to whom, and
launch the result as a running team. No dependencies.

Every function takes a state map and returns a new one. No processes, no
storage, no rendering — so the whole editor is testable without a browser, and
the same transitions drive a LiveView, a CLI, or a test.

## The three graphs

A canvas holds agents plus two independent edge sets over them:

**Spawn links** — who starts whom. A forest that determines launch order.

**Comm rules** — who may message whom, `"allow"` for a direct channel and
`"route"` for one via a relay.

They are deliberately separate. An agent that spawns another usually talks to
it, but a coordinator that spawns a whole team may want its workers talking only
to a lead. Collapsing the two would make that inexpressible.

Spawn links dedup in both directions — a link between two slots is one link.
Comm rules are directional: A may message B without B being able to reply.

## Install

```elixir
def deps do
  [{:workshop_canvas, path: "../workshop_canvas"}]
end
```

## Use

```elixir
state =
  WorkshopCanvas.defaults()
  |> WorkshopCanvas.add_agent(%{name: "coordinator", capability: "coordinator"})
  |> WorkshopCanvas.add_agent(%{name: "builder"})
  |> WorkshopCanvas.add_spawn_link(1, 2)
  |> WorkshopCanvas.add_comm_rule(1, 2, "allow")

WorkshopCanvas.spawn_order(state)            #=> [coordinator, builder]
WorkshopCanvas.problems(state)               #=> []
WorkshopCanvas.to_persistence_params(state)

# editing
WorkshopCanvas.move_agent(state, 1, 500, 400)
WorkshopCanvas.update_agent(state, 1, %{"persona" => "You coordinate."})
WorkshopCanvas.remove_agent(state, 1)
```

### State shape

State is a plain map with `ws_`-prefixed keys, so it merges directly into a
larger LiveView assigns map without colliding with anything else — and
`clear/1` wipes the canvas without touching the rest of the page.

```elixir
%{
  ws_agents: [],           ws_spawn_links: [],   ws_comm_rules: [],
  ws_selected_agent: nil,  ws_next_id: 1,        ws_team_id: nil,
  ws_team_name: "alpha",   ws_strategy: "one_for_one",
  ws_default_model: "sonnet", ws_cwd: ""
}
```

## Design notes

**Removal cascades.** Deleting an agent also drops every spawn link and comm
rule that referenced it — including rules that named it only as a `via` relay.
A leftover rule would render as `unknown-4` in the generated prompt, or route
messages through a slot that no longer exists.

**Agents always carry every key.** The canvas edits with map-update syntax, which
raises on a missing key. Filling the map at construction means a sparse preset
or a record persisted before a field existed cannot blow up the first time
someone edits it. `apply_team/2` runs loaded agents through
`WorkshopCanvas.Agent.complete/1` for the same reason.

**`ws_next_id` is derived, never trusted.** On load it comes from the highest
slot id present. A stored counter goes stale the moment anything edits the agent
list, and the result is a duplicate slot id.

**`problems/1` reports what would misbehave at launch** — duplicate names,
dangling links and rules, spawn cycles. Duplicate names matter because session
ids are built as `<session>-<name>`, so two agents sharing a name share an
inbox.

## Spawn order

`WorkshopCanvas.Topology.spawn_order/2` walks the spawn forest depth-first, so
every parent starts before its children. A canvas is drawn by hand and is not
guaranteed to be a tree, so two cases get explicit handling:

- a **cycle** would make a naive walk recurse forever
- a **diamond** — two parents, one child — would emit the child twice, and
  launching an agent twice is a real failure

Both are handled by tracking what has been emitted. Anything reachable only
inside a cycle is appended at the end, so every agent launches exactly once even
when the drawing is nonsense. `Topology.unreachable/2` reports those ids if you
want to warn before launching instead.

## Presets

A preset is a named starting layout. Registering your own is the point — the one
built-in exists to document the shape.

```elixir
config :workshop_canvas, presets: %{
  "review" => %WorkshopCanvas.Preset{
    label: "Code review",
    color: "#7c3aed",
    team_name: "review",
    agents: [
      %{id: 1, name: "lead", capability: "coordinator"},
      %{id: 2, name: "reviewer", capability: "scout"}
    ],
    links: [%{from: 1, to: 2}],
    rules: [%{from: 1, to: 2, policy: "allow", via: nil}]
  }
}
```

```elixir
Preset.ui_list()               #=> [%{name: ..., label: ..., color: ...}]
Preset.apply(state, "review")
```

Configured presets replace the built-in map rather than merging, so you are
never stuck with an example you did not ask for. Preset agents only state what
differs from the defaults; the rest is filled in on apply. An unknown name
returns the state untouched, so a stale button cannot blank someone's canvas.

## Configuration

```elixir
config :workshop_canvas,
  default_team_name: "alpha",
  default_strategy: "one_for_one",
  default_model: "sonnet",
  default_capability: "builder",
  default_permission: "default",
  default_quality_gates: "mix compile --warnings-as-errors",
  grid_columns: 3,
  grid_x_origin: 40,   grid_y_origin: 30,
  grid_x_spacing: 230, grid_y_spacing: 170
```

## Tests

```
mix test
```

88 tests and 8 doctests covering every transition, removal cascades, the
persistence round-trip, preset application, and the cycle and diamond cases in
spawn ordering.

## Changes from the original

- Namespace `Ichor.Workshop.CanvasState` → `WorkshopCanvas`, with agent
  construction in `WorkshopCanvas.Agent`, ordering in `.Topology`, and presets
  in `.Preset`.
- The `AgentSlot`, `CommRule`, and `SpawnLink` Ash embedded resources became
  plain maps.
- Defaults and grid layout moved from module attributes to configuration.
- **The 799-line preset module was left behind.** Its own moduledoc described
  the personas as hardcoded mock data awaiting replacement, so porting them
  would have preserved throwaway content. The mechanism came across; one small
  example preset stands in.

Fixed along the way:

- **`spawn_order/2` recursed forever on a cycle**, and emitted an agent twice
  when two parents shared a child. It now tracks what it has emitted.
- **A cycle silently dropped agents from the launch.** With every node parented,
  there were no roots, so the walk returned fewer agents than it was given —
  and the caller launched a partial team with no error. Unreachable agents are
  now appended rather than lost.
- **`apply_team/2` trusted the loaded agent list for `ws_next_id`** via
  `max_slot + 1` on possibly-incomplete records, and did not fill in missing
  agent fields, so an older persisted team crashed on first edit.

Added: `problems/1`, `Topology.unreachable/2`, `children_of/2`,
`selected_agent/1`, `get_agent/2`, and a `via` argument on `add_comm_rule/5` —
the state supported routed rules but nothing could create one.
