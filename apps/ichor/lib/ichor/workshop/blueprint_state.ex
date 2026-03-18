defmodule Ichor.Workshop.BlueprintState do
  @moduledoc """
  Pure state transitions for the Workshop canvas.
  """

  @type agent :: %{
          id: integer(),
          name: String.t(),
          capability: String.t(),
          model: String.t(),
          permission: String.t(),
          persona: String.t(),
          file_scope: String.t(),
          quality_gates: String.t(),
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
          ws_blueprint_id: String.t() | nil
        }

  @default_quality_gates "mix compile --warnings-as-errors"

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
      ws_blueprint_id: nil
    }
  end

  @spec clear(map()) :: map()
  def clear(state) do
    Map.merge(state, defaults())
  end

  @spec add_agent(t(), map()) :: t()
  def add_agent(state, attrs) do
    agent = new_agent(state, attrs)

    state
    |> Map.update!(:ws_agents, &(&1 ++ [agent]))
    |> Map.put(:ws_next_id, state.ws_next_id + 1)
    |> Map.put(:ws_selected_agent, agent.id)
  end

  @spec select_agent(t(), integer()) :: t()
  def select_agent(state, id), do: Map.put(state, :ws_selected_agent, id)

  @spec move_agent(t(), integer(), integer(), integer()) :: t()
  def move_agent(state, id, x, y) do
    update_agents(state, fn agent ->
      if agent.id == id, do: %{agent | x: x, y: y}, else: agent
    end)
  end

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

  @spec remove_spawn_link(t(), integer()) :: t()
  def remove_spawn_link(state, index) do
    Map.update!(state, :ws_spawn_links, &List.delete_at(&1, index))
  end

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

  @spec remove_comm_rule(t(), integer()) :: t()
  def remove_comm_rule(state, index) do
    Map.update!(state, :ws_comm_rules, &List.delete_at(&1, index))
  end

  @spec update_team(t(), map()) :: t()
  def update_team(state, params) do
    state
    |> Map.put(:ws_team_name, Map.get(params, "name", state.ws_team_name))
    |> Map.put(:ws_strategy, Map.get(params, "strategy", state.ws_strategy))
    |> Map.put(:ws_default_model, Map.get(params, "default_model", state.ws_default_model))
    |> Map.put(:ws_cwd, Map.get(params, "cwd", state.ws_cwd))
  end

  @spec apply_blueprint(t(), map()) :: t()
  def apply_blueprint(state, blueprint) do
    agents = Enum.map(blueprint.agent_blueprints, &ash_to_agent/1)
    links = Enum.map(blueprint.spawn_links, &ash_to_link/1)
    rules = Enum.map(blueprint.comm_rules, &ash_to_rule/1)
    max_slot = agents |> Enum.map(& &1.id) |> Enum.max(fn -> 0 end)

    state
    |> Map.put(:ws_blueprint_id, blueprint.id)
    |> Map.put(:ws_team_name, blueprint.name)
    |> Map.put(:ws_strategy, blueprint.strategy)
    |> Map.put(:ws_default_model, blueprint.default_model)
    |> Map.put(:ws_cwd, blueprint.cwd || "")
    |> Map.put(:ws_agents, agents)
    |> Map.put(:ws_spawn_links, links)
    |> Map.put(:ws_comm_rules, rules)
    |> Map.put(:ws_selected_agent, nil)
    |> Map.put(:ws_next_id, max_slot + 1)
  end

  @spec new_agent(t(), map()) :: agent()
  def new_agent(state, attrs) do
    count = length(state.ws_agents)
    x = 40 + rem(count, 3) * 230
    y = 30 + div(count, 3) * 170

    %{
      id: state.ws_next_id,
      name: Map.fetch!(attrs, :name),
      capability: Map.get(attrs, :capability, "builder"),
      model: Map.get(attrs, :model, state.ws_default_model),
      permission: Map.get(attrs, :permission, "default"),
      persona: Map.get(attrs, :persona, ""),
      file_scope: Map.get(attrs, :file_scope, ""),
      quality_gates: Map.get(attrs, :quality_gates, @default_quality_gates),
      x: Map.get(attrs, :x, x),
      y: Map.get(attrs, :y, y)
    }
  end

  @spec agent_type_agent(t(), map(), non_neg_integer()) :: agent()
  def agent_type_agent(state, type, index) do
    new_agent(state, %{
      name: "#{type.name}-#{index}",
      capability: type.capability,
      model: type.default_model,
      permission: type.default_permission,
      persona: type.default_persona || "",
      file_scope: type.default_file_scope || "",
      quality_gates: type.default_quality_gates || ""
    })
  end

  @spec to_persistence_params(t()) :: map()
  def to_persistence_params(state) do
    %{
      name: state.ws_team_name,
      strategy: state.ws_strategy,
      default_model: state.ws_default_model,
      cwd: state.ws_cwd,
      agent_blueprints: Enum.map(state.ws_agents, &agent_to_ash/1),
      spawn_links: Enum.map(state.ws_spawn_links, &link_to_ash/1),
      comm_rules: Enum.map(state.ws_comm_rules, &rule_to_ash/1)
    }
  end

  defp update_agents(state, fun) do
    Map.update!(state, :ws_agents, fn agents -> Enum.map(agents, fun) end)
  end

  defp agent_to_ash(agent) do
    %{
      slot: agent.id,
      name: agent.name,
      capability: agent.capability,
      model: agent.model,
      permission: agent.permission,
      persona: agent.persona || "",
      file_scope: agent.file_scope || "",
      quality_gates: agent.quality_gates || "",
      canvas_x: agent.x,
      canvas_y: agent.y
    }
  end

  defp ash_to_agent(agent) do
    %{
      id: agent.slot,
      name: agent.name,
      capability: agent.capability,
      model: agent.model,
      permission: agent.permission,
      persona: agent.persona || "",
      file_scope: agent.file_scope || "",
      quality_gates: agent.quality_gates || "",
      x: agent.canvas_x,
      y: agent.canvas_y
    }
  end

  defp link_to_ash(link), do: %{from_slot: link.from, to_slot: link.to}
  defp ash_to_link(link), do: %{from: link.from_slot, to: link.to_slot}

  defp rule_to_ash(rule),
    do: %{from_slot: rule.from, to_slot: rule.to, policy: rule.policy, via_slot: rule.via}

  defp ash_to_rule(rule),
    do: %{from: rule.from_slot, to: rule.to_slot, policy: rule.policy, via: rule.via_slot}
end
