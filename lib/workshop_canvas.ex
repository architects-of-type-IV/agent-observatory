defmodule WorkshopCanvas do
  @moduledoc """
  Pure state transitions for a visual agent-team designer.

  Extracted from the ICHOR IV agent observatory, where a drag-and-drop canvas
  let you place agents, wire up who spawns whom, and declare who may talk to
  whom, then launch the result as a running team.

  Every function here takes a state map and returns a new one. No processes, no
  storage, no rendering — which means the whole editor is testable without a
  browser, and the same transitions drive a LiveView, a CLI, or a test.

  ## The three graphs

  A canvas holds agents plus two independent edge sets over them:

  **Spawn links** — who starts whom. A forest that determines launch order; see
  `WorkshopCanvas.Topology.spawn_order/2`.

  **Comm rules** — who may message whom, with `"allow"` for a direct channel and
  `"route"` for one via a relay.

  They are deliberately separate. An agent that spawns another usually talks to
  it, but a coordinator that spawns a whole team may want its workers talking
  only to a lead. Collapsing the two would make that inexpressible.

  ## State shape

  State is a plain map with `ws_`-prefixed keys, so it can be merged directly
  into a larger LiveView assigns map without colliding with anything else:

      %{
        ws_agents: [],           ws_spawn_links: [],   ws_comm_rules: [],
        ws_selected_agent: nil,  ws_next_id: 1,        ws_team_id: nil,
        ws_team_name: "alpha",   ws_strategy: "one_for_one",
        ws_default_model: "sonnet", ws_cwd: ""
      }

  Functions use `Map.update!/3`, so passing a map missing these keys raises
  rather than silently building a half-canvas.

  ## Example

      state =
        WorkshopCanvas.defaults()
        |> WorkshopCanvas.add_agent(%{name: "coordinator", capability: "coordinator"})
        |> WorkshopCanvas.add_agent(%{name: "builder"})
        |> WorkshopCanvas.add_spawn_link(1, 2)
        |> WorkshopCanvas.add_comm_rule(1, 2, "allow")

      WorkshopCanvas.spawn_order(state)          #=> [coordinator, builder]
      WorkshopCanvas.to_persistence_params(state)
  """

  alias WorkshopCanvas.Agent
  alias WorkshopCanvas.Config
  alias WorkshopCanvas.Topology

  @typedoc "A spawn link: `from` starts `to`."
  @type spawn_link :: %{from: integer(), to: integer()}

  @typedoc "A comm rule. `policy` is `\"allow\"` or `\"route\"`; `via` names the relay."
  @type comm_rule :: %{
          from: integer(),
          to: integer(),
          policy: String.t(),
          via: integer() | nil
        }

  @type t :: %{
          ws_agents: [Agent.t()],
          ws_spawn_links: [spawn_link()],
          ws_comm_rules: [comm_rule()],
          ws_selected_agent: integer() | nil,
          ws_next_id: integer(),
          ws_team_name: String.t(),
          ws_strategy: String.t(),
          ws_default_model: String.t(),
          ws_cwd: String.t(),
          ws_team_id: String.t() | nil
        }

  @doc "A fresh, empty canvas."
  @spec defaults() :: t()
  def defaults do
    %{
      ws_agents: [],
      ws_spawn_links: [],
      ws_comm_rules: [],
      ws_selected_agent: nil,
      ws_next_id: 1,
      ws_team_name: Config.default_team_name(),
      ws_strategy: Config.default_strategy(),
      ws_default_model: Config.default_model(),
      ws_cwd: "",
      ws_team_id: nil
    }
  end

  @doc """
  Reset the canvas fields of a larger state map, leaving everything else alone.

  This is why the keys are prefixed: `clear/1` on a LiveView's assigns wipes the
  canvas without touching the rest of the page.
  """
  @spec clear(map()) :: map()
  def clear(state), do: Map.merge(state, defaults())

  # Agents

  @doc """
  Place a new agent, auto-positioned, and select it.

  The new agent takes `ws_next_id`, which then advances — so ids are stable for
  the life of a canvas even as agents are removed.
  """
  @spec add_agent(t(), map()) :: t()
  def add_agent(state, attrs) do
    agent = new_agent(state, attrs)

    state
    |> Map.update!(:ws_agents, &(&1 ++ [agent]))
    |> Map.put(:ws_next_id, state.ws_next_id + 1)
    |> Map.put(:ws_selected_agent, agent.id)
  end

  @doc "Build an agent for this canvas without adding it."
  @spec new_agent(t(), map()) :: Agent.t()
  def new_agent(state, attrs) do
    Agent.build(attrs,
      id: state.ws_next_id,
      index: length(state.ws_agents),
      default_model: state.ws_default_model
    )
  end

  @doc """
  Build a canvas agent from a reusable agent-type record.

  `type` supplies `name`, `capability`, and the `default_*` fields; `index`
  disambiguates several agents of the same type.
  """
  @spec agent_type_agent(t(), map(), non_neg_integer()) :: Agent.t()
  def agent_type_agent(state, type, index) do
    new_agent(state, %{
      name: "#{Map.get(type, :name)}-#{index}",
      capability: Map.get(type, :capability),
      model: Map.get(type, :default_model),
      permission: Map.get(type, :default_permission),
      persona: Map.get(type, :default_persona),
      file_scope: Map.get(type, :default_file_scope),
      quality_gates: Map.get(type, :default_quality_gates),
      tools: Map.get(type, :default_tools),
      agent_type_id: Map.get(type, :id)
    })
  end

  @doc "Mark an agent as selected."
  @spec select_agent(t(), integer() | nil) :: t()
  def select_agent(state, id), do: Map.put(state, :ws_selected_agent, id)

  @doc "Move an agent to new coordinates."
  @spec move_agent(t(), integer(), integer(), integer()) :: t()
  def move_agent(state, id, x, y) do
    update_agent_by_id(state, id, &%{&1 | x: x, y: y})
  end

  @doc """
  Apply form params to an agent.

  Params are string-keyed, as they arrive from a form; unsupplied fields keep
  their current values. Position and identity are not editable here — use
  `move_agent/4`.
  """
  @spec update_agent(t(), integer(), map()) :: t()
  def update_agent(state, id, params) do
    update_agent_by_id(state, id, fn agent ->
      Enum.reduce(
        [:name, :capability, :model, :permission, :persona, :file_scope, :quality_gates],
        agent,
        fn field, acc ->
          Map.put(acc, field, Map.get(params, to_string(field), Map.get(acc, field)))
        end
      )
    end)
  end

  @doc """
  Remove an agent along with every link and rule that referenced it.

  Cascading matters: a rule pointing at a deleted slot would render as
  `unknown-4` in the generated prompt, or route a message nowhere.
  """
  @spec remove_agent(t(), integer()) :: t()
  def remove_agent(state, id) do
    state
    |> Map.update!(:ws_agents, &Enum.reject(&1, fn agent -> agent.id == id end))
    |> Map.update!(:ws_spawn_links, &Enum.reject(&1, fn l -> l.from == id or l.to == id end))
    |> Map.update!(:ws_comm_rules, fn rules -> Enum.reject(rules, &references?(&1, id)) end)
    |> Map.put(:ws_selected_agent, nil)
  end

  # Links and rules

  @doc """
  Link `from` as the spawner of `to`. Idempotent, and undirected for dedup —
  a link between two slots is not added twice in either direction.
  """
  @spec add_spawn_link(t(), integer(), integer()) :: t()
  def add_spawn_link(state, from, to) do
    exists? =
      Enum.any?(state.ws_spawn_links, fn l ->
        (l.from == from and l.to == to) or (l.from == to and l.to == from)
      end)

    if exists? do
      state
    else
      Map.update!(state, :ws_spawn_links, &(&1 ++ [%{from: from, to: to}]))
    end
  end

  @doc "Remove the spawn link at `index`."
  @spec remove_spawn_link(t(), integer()) :: t()
  def remove_spawn_link(state, index),
    do: Map.update!(state, :ws_spawn_links, &List.delete_at(&1, index))

  @doc """
  Permit `from` to message `to`. Idempotent per `{from, to, policy}`.

  Unlike spawn links this is directional: A may message B without B being able
  to reply.
  """
  @spec add_comm_rule(t(), integer(), integer(), String.t(), integer() | nil) :: t()
  def add_comm_rule(state, from, to, policy, via \\ nil) do
    exists? =
      Enum.any?(state.ws_comm_rules, fn r ->
        r.from == from and r.to == to and r.policy == policy
      end)

    if exists? do
      state
    else
      rule = %{from: from, to: to, policy: policy, via: via}
      Map.update!(state, :ws_comm_rules, &(&1 ++ [rule]))
    end
  end

  @doc "Remove the comm rule at `index`."
  @spec remove_comm_rule(t(), integer()) :: t()
  def remove_comm_rule(state, index),
    do: Map.update!(state, :ws_comm_rules, &List.delete_at(&1, index))

  # Team-level

  @doc "Apply team-level form params: name, strategy, default_model, cwd."
  @spec update_team(t(), map()) :: t()
  def update_team(state, params) do
    %{
      state
      | ws_team_name: Map.get(params, "name", state.ws_team_name),
        ws_strategy: Map.get(params, "strategy", state.ws_strategy),
        ws_default_model: Map.get(params, "default_model", state.ws_default_model),
        ws_cwd: Map.get(params, "cwd", state.ws_cwd)
    }
  end

  @doc """
  Load a persisted team onto the canvas.

  Agents are completed through `WorkshopCanvas.Agent.complete/1`, so a record
  written before a field existed still edits cleanly. `ws_next_id` is derived
  from the highest slot id present rather than trusted from the record.
  """
  @spec apply_team(t(), map()) :: t()
  def apply_team(state, team) do
    agents = team |> Map.get(:agents) |> to_maps() |> Enum.map(&Agent.complete/1)
    links = team |> Map.get(:spawn_links) |> to_maps()
    rules = team |> Map.get(:comm_rules) |> to_maps()

    state
    |> Map.put(:ws_team_id, Map.get(team, :id))
    |> Map.put(:ws_team_name, Map.get(team, :name) || Config.default_team_name())
    |> Map.put(:ws_strategy, Map.get(team, :strategy) || Config.default_strategy())
    |> Map.put(:ws_default_model, Map.get(team, :default_model) || Config.default_model())
    |> Map.put(:ws_cwd, Map.get(team, :cwd) || "")
    |> Map.put(:ws_agents, agents)
    |> Map.put(:ws_spawn_links, links)
    |> Map.put(:ws_comm_rules, rules)
    |> Map.put(:ws_selected_agent, nil)
    |> Map.put(:ws_next_id, next_id(agents))
  end

  @doc "The canvas as params for creating or updating a persisted team."
  @spec to_persistence_params(t()) :: map()
  def to_persistence_params(state) do
    %{
      name: state.ws_team_name,
      strategy: state.ws_strategy,
      default_model: state.ws_default_model,
      cwd: state.ws_cwd,
      agents: state.ws_agents,
      spawn_links: state.ws_spawn_links,
      comm_rules: state.ws_comm_rules
    }
  end

  # Queries

  @doc "Agents in depth-first spawn order. See `WorkshopCanvas.Topology.spawn_order/2`."
  @spec spawn_order(t()) :: [Agent.t()]
  def spawn_order(state), do: Topology.spawn_order(state.ws_agents, state.ws_spawn_links)

  @doc "The currently selected agent, or `nil`."
  @spec selected_agent(t()) :: Agent.t() | nil
  def selected_agent(%{ws_selected_agent: nil}), do: nil

  def selected_agent(state),
    do: Enum.find(state.ws_agents, &(&1.id == state.ws_selected_agent))

  @doc "Look up an agent by slot id."
  @spec get_agent(t(), integer()) :: Agent.t() | nil
  def get_agent(state, id), do: Enum.find(state.ws_agents, &(&1.id == id))

  @doc """
  Problems that would make this canvas misbehave once launched.

  Returns a list of `{:duplicate_name, name}`, `{:dangling_link, link}`,
  `{:dangling_rule, rule}`, and `{:spawn_cycle, ids}`. An empty list means the
  drawing is coherent.

  Duplicate names matter because session ids are built as `<session>-<name>`,
  so two agents sharing a name share an inbox.
  """
  @spec problems(t()) :: [tuple()]
  def problems(state) do
    ids = MapSet.new(state.ws_agents, & &1.id)

    duplicate_names =
      state.ws_agents
      |> Enum.frequencies_by(& &1.name)
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Enum.map(fn {name, _} -> {:duplicate_name, name} end)

    dangling_links =
      state.ws_spawn_links
      |> Enum.reject(&(MapSet.member?(ids, &1.from) and MapSet.member?(ids, &1.to)))
      |> Enum.map(&{:dangling_link, &1})

    dangling_rules =
      state.ws_comm_rules
      |> Enum.reject(&(MapSet.member?(ids, &1.from) and MapSet.member?(ids, &1.to)))
      |> Enum.map(&{:dangling_rule, &1})

    cycles =
      case Topology.unreachable(state.ws_agents, state.ws_spawn_links) do
        [] -> []
        ids -> [{:spawn_cycle, ids}]
      end

    duplicate_names ++ dangling_links ++ dangling_rules ++ cycles
  end

  # Private

  defp update_agent_by_id(state, id, fun) do
    Map.update!(state, :ws_agents, fn agents ->
      Enum.map(agents, fn agent -> if agent.id == id, do: fun.(agent), else: agent end)
    end)
  end

  defp references?(rule, id), do: rule.from == id or rule.to == id or Map.get(rule, :via) == id

  defp to_maps(nil), do: []
  defp to_maps(list) when is_list(list), do: Enum.map(list, &to_map/1)
  defp to_maps(_), do: []

  defp to_map(%{__struct__: _} = struct), do: Map.from_struct(struct)
  defp to_map(map) when is_map(map), do: map

  defp next_id([]), do: 1
  defp next_id(agents), do: (agents |> Enum.map(& &1.id) |> Enum.max()) + 1
end
