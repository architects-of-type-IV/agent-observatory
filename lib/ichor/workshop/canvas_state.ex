defmodule Ichor.Workshop.CanvasState do
  @moduledoc """
  Pure state transitions for the Workshop canvas.
  """

  @type agent :: %{
          id: integer(),
          agent_type_id: String.t() | nil,
          name: String.t(),
          capability: String.t(),
          model: String.t(),
          permission: String.t(),
          persona: String.t(),
          file_scope: String.t(),
          quality_gates: String.t(),
          tools: [String.t()],
          x: integer(),
          y: integer()
        }

  @type spawn_link :: %{from: integer(), to: integer()}
  @type comm_rule :: %{from: integer(), to: integer(), policy: String.t(), via: integer() | nil}

  @type t :: %{
          ws_agents: [agent()],
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

  @default_quality_gates "mix compile --warnings-as-errors"

  @doc "Return the default Workshop canvas state."
  @spec defaults() :: map()
  def defaults do
    %{
      ws_agents: [],
      ws_spawn_links: [],
      ws_comm_rules: [],
      ws_selected_agent: nil,
      ws_next_id: 1,
      ws_team_name: "alpha",
      ws_strategy: "one_for_one",
      ws_default_model: "sonnet",
      ws_cwd: "",
      ws_team_id: nil
    }
  end

  @doc "Reset all workshop canvas fields to defaults."
  @spec clear(map()) :: map()
  def clear(state) do
    Map.merge(state, defaults())
  end

  @doc "Add a new agent to the canvas, returning the updated state."
  @spec add_agent(t(), map()) :: t()
  def add_agent(state, attrs) do
    agent = new_agent(state, attrs)

    state
    |> Map.update!(:ws_agents, &(&1 ++ [agent]))
    |> Map.put(:ws_next_id, state.ws_next_id + 1)
    |> Map.put(:ws_selected_agent, agent.id)
  end

  @doc "Set the selected agent id in state."
  @spec select_agent(t(), integer()) :: t()
  def select_agent(state, id), do: Map.put(state, :ws_selected_agent, id)

  @doc "Move an agent to new canvas coordinates."
  @spec move_agent(t(), integer(), integer(), integer()) :: t()
  def move_agent(state, id, x, y) do
    update_agents(state, fn agent ->
      if agent.id == id, do: %{agent | x: x, y: y}, else: agent
    end)
  end

  @doc "Apply param changes to a specific agent by id."
  @spec update_agent(t(), integer(), map()) :: t()
  def update_agent(state, id, params) do
    update_agents(state, fn agent ->
      if agent.id == id do
        %{
          agent
          | name: Map.get(params, "name", agent.name),
            capability: Map.get(params, "capability", agent.capability),
            model: Map.get(params, "model", agent.model),
            permission: Map.get(params, "permission", agent.permission),
            persona: Map.get(params, "persona", agent.persona),
            file_scope: Map.get(params, "file_scope", agent.file_scope),
            quality_gates: Map.get(params, "quality_gates", agent.quality_gates)
        }
      else
        agent
      end
    end)
  end

  @doc "Remove an agent and its associated links and rules from state."
  @spec remove_agent(t(), integer()) :: t()
  def remove_agent(state, id) do
    state
    |> Map.update!(:ws_agents, &Enum.reject(&1, fn agent -> agent.id == id end))
    |> Map.update!(
      :ws_spawn_links,
      &Enum.reject(&1, fn link -> link.from == id or link.to == id end)
    )
    |> Map.update!(:ws_comm_rules, fn rules ->
      Enum.reject(rules, fn rule -> rule.from == id or rule.to == id or rule.via == id end)
    end)
    |> Map.put(:ws_selected_agent, nil)
  end

  @doc "Add a spawn link between two agent slots (idempotent)."
  @spec add_spawn_link(t(), integer(), integer()) :: t()
  def add_spawn_link(state, from, to) do
    already? =
      Enum.any?(state.ws_spawn_links, fn link ->
        (link.from == from and link.to == to) or (link.from == to and link.to == from)
      end)

    if already? do
      state
    else
      Map.update!(state, :ws_spawn_links, &(&1 ++ [%{from: from, to: to}]))
    end
  end

  @doc "Remove a spawn link at the given index."
  @spec remove_spawn_link(t(), integer()) :: t()
  def remove_spawn_link(state, index) do
    Map.update!(state, :ws_spawn_links, &List.delete_at(&1, index))
  end

  @doc "Add a communication rule between two agent slots (idempotent)."
  @spec add_comm_rule(t(), integer(), integer(), String.t()) :: t()
  def add_comm_rule(state, from, to, policy) do
    exists? =
      Enum.any?(state.ws_comm_rules, fn rule ->
        rule.from == from and rule.to == to and rule.policy == policy
      end)

    if exists? do
      state
    else
      Map.update!(
        state,
        :ws_comm_rules,
        &(&1 ++ [%{from: from, to: to, policy: policy, via: nil}])
      )
    end
  end

  @doc "Remove a communication rule at the given index."
  @spec remove_comm_rule(t(), integer()) :: t()
  def remove_comm_rule(state, index) do
    Map.update!(state, :ws_comm_rules, &List.delete_at(&1, index))
  end

  @doc "Apply team-level param changes (name, strategy, default_model, cwd)."
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

  @doc "Apply a persisted team record to the canvas state."
  @spec apply_team(t(), map()) :: t()
  def apply_team(state, team) do
    agents = Enum.map(team.agents || [], &Map.from_struct/1)
    links = Enum.map(team.spawn_links || [], &Map.from_struct/1)
    rules = Enum.map(team.comm_rules || [], &Map.from_struct/1)
    max_slot = agents |> Enum.map(& &1.id) |> Enum.max(fn -> 0 end)

    state
    |> Map.put(:ws_team_id, team.id)
    |> Map.put(:ws_team_name, team.name)
    |> Map.put(:ws_strategy, team.strategy)
    |> Map.put(:ws_default_model, team.default_model)
    |> Map.put(:ws_cwd, team.cwd || "")
    |> Map.put(:ws_agents, agents)
    |> Map.put(:ws_spawn_links, links)
    |> Map.put(:ws_comm_rules, rules)
    |> Map.put(:ws_selected_agent, nil)
    |> Map.put(:ws_next_id, max_slot + 1)
  end

  @doc "Build a new agent map with auto-positioned canvas coordinates."
  @spec new_agent(t(), map()) :: agent()
  def new_agent(state, attrs) do
    count = length(state.ws_agents)
    x = 40 + rem(count, 3) * 230
    y = 30 + div(count, 3) * 170

    %{
      id: state.ws_next_id,
      agent_type_id: Map.get(attrs, :agent_type_id),
      name: Map.fetch!(attrs, :name),
      capability: Map.get(attrs, :capability, "builder"),
      model: Map.get(attrs, :model, state.ws_default_model),
      permission: Map.get(attrs, :permission, "default"),
      persona: Map.get(attrs, :persona, ""),
      file_scope: Map.get(attrs, :file_scope, ""),
      quality_gates: Map.get(attrs, :quality_gates, @default_quality_gates),
      tools: Map.get(attrs, :tools, []),
      x: Map.get(attrs, :x, x),
      y: Map.get(attrs, :y, y)
    }
  end

  @doc "Build a canvas agent from an AgentType record and a position index."
  @spec agent_type_agent(t(), map(), non_neg_integer()) :: agent()
  def agent_type_agent(state, type, index) do
    new_agent(state, %{
      name: "#{type.name}-#{index}",
      capability: type.capability,
      model: type.default_model,
      permission: type.default_permission,
      persona: type.default_persona || "",
      file_scope: type.default_file_scope || "",
      quality_gates: type.default_quality_gates || "",
      tools: type.default_tools || [],
      agent_type_id: type.id
    })
  end

  @doc "Convert workshop state to persistence params for team create/update."
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

  defp update_agents(state, fun) do
    Map.update!(state, :ws_agents, fn agents -> Enum.map(agents, fun) end)
  end
end
