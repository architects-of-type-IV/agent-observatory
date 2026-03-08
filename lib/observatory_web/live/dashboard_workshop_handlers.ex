defmodule ObservatoryWeb.DashboardWorkshopHandlers do
  @moduledoc """
  Canvas event handlers for the Workshop team builder.
  Blueprint CRUD in WorkshopPersistence. Types in WorkshopTypes.
  Presets in WorkshopPresets.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Observatory.Workshop.TeamBlueprint
  alias ObservatoryWeb.WorkshopPersistence, as: WP
  alias ObservatoryWeb.WorkshopPresets

  defdelegate list_blueprints, to: WP
  defdelegate list_agent_types, to: WP
  defdelegate push_ws_state(socket), to: WP

  def handle_event("ws_add_agent", _, socket) do
    agent = new_agent(socket, %{
      name: "agent-#{length(socket.assigns.ws_agents) + 1}",
      capability: "builder", model: socket.assigns.ws_default_model,
      permission: "default", persona: "", file_scope: "",
      quality_gates: "mix compile --warnings-as-errors"
    })

    {:noreply, socket |> append_agent(agent) |> save_and_push()}
  end

  def handle_event("ws_add_agent_from_type", %{"id" => id}, socket) do
    case Observatory.Workshop.AgentType.by_id(id) do
      {:ok, type} ->
        agent = new_agent(socket, %{
          name: "#{type.name}-#{length(socket.assigns.ws_agents) + 1}",
          capability: type.capability, model: type.default_model,
          permission: type.default_permission,
          persona: type.default_persona || "", file_scope: type.default_file_scope || "",
          quality_gates: type.default_quality_gates || ""
        })

        {:noreply, socket |> append_agent(agent) |> save_and_push()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("ws_select_agent", %{"id" => id}, socket) do
    {:noreply, socket |> assign(:ws_selected_agent, to_int(id)) |> push_ws_state()}
  end

  def handle_event("ws_move_agent", %{"id" => id, "x" => x, "y" => y}, socket) do
    id = to_int(id)
    agents = Enum.map(socket.assigns.ws_agents, fn a ->
      if a.id == id, do: %{a | x: x, y: y}, else: a
    end)

    {:noreply, socket |> assign(:ws_agents, agents) |> WP.auto_save()}
  end

  def handle_event("ws_update_agent", params, socket) do
    case socket.assigns.ws_selected_agent do
      nil ->
        {:noreply, socket}

      id ->
        agents = Enum.map(socket.assigns.ws_agents, fn a ->
          if a.id == id, do: merge_agent(a, params), else: a
        end)

        {:noreply, socket |> assign(:ws_agents, agents) |> save_and_push()}
    end
  end

  def handle_event("ws_remove_agent", _, socket) do
    case socket.assigns.ws_selected_agent do
      nil ->
        {:noreply, socket}

      id ->
        socket
        |> assign(:ws_agents, Enum.reject(socket.assigns.ws_agents, &(&1.id == id)))
        |> assign(:ws_spawn_links, Enum.reject(socket.assigns.ws_spawn_links, fn l -> l.from == id || l.to == id end))
        |> assign(:ws_comm_rules, Enum.reject(socket.assigns.ws_comm_rules, fn r -> r.from == id || r.to == id || r.via == id end))
        |> assign(:ws_selected_agent, nil)
        |> save_and_push()
        |> then(&{:noreply, &1})
    end
  end

  def handle_event("ws_add_spawn_link", %{"from" => from, "to" => to}, socket) do
    from = to_int(from)
    to = to_int(to)
    links = socket.assigns.ws_spawn_links

    already? = Enum.any?(links, fn l -> (l.from == from && l.to == to) || (l.from == to && l.to == from) end)

    if already?,
      do: {:noreply, socket},
      else: {:noreply, socket |> assign(:ws_spawn_links, links ++ [%{from: from, to: to}]) |> save_and_push()}
  end

  def handle_event("ws_add_comm_rule", %{"from" => from, "to" => to, "policy" => policy}, socket) do
    from = to_int(from)
    to = to_int(to)
    rules = socket.assigns.ws_comm_rules
    exists? = Enum.any?(rules, fn r -> r.from == from && r.to == to && r.policy == policy end)

    if exists?,
      do: {:noreply, socket},
      else: {:noreply, socket |> assign(:ws_comm_rules, rules ++ [%{from: from, to: to, policy: policy, via: nil}]) |> save_and_push()}
  end

  def handle_event("ws_remove_spawn_link", %{"index" => idx}, socket) do
    {:noreply, socket |> assign(:ws_spawn_links, List.delete_at(socket.assigns.ws_spawn_links, to_int(idx))) |> save_and_push()}
  end

  def handle_event("ws_remove_comm_rule", %{"index" => idx}, socket) do
    {:noreply, socket |> assign(:ws_comm_rules, List.delete_at(socket.assigns.ws_comm_rules, to_int(idx))) |> save_and_push()}
  end

  def handle_event("ws_update_team", params, socket) do
    {:noreply,
      socket
      |> assign(:ws_team_name, params["name"] || socket.assigns.ws_team_name)
      |> assign(:ws_strategy, params["strategy"] || socket.assigns.ws_strategy)
      |> assign(:ws_default_model, params["default_model"] || socket.assigns.ws_default_model)
      |> assign(:ws_cwd, params["cwd"] || socket.assigns.ws_cwd)
      |> WP.auto_save()}
  end

  def handle_event("ws_preset", %{"name" => name}, socket) do
    {:noreply, socket |> WP.clear_canvas() |> WorkshopPresets.apply(name) |> save_and_push()}
  end

  def handle_event("ws_clear", _, socket) do
    if bp_id = socket.assigns[:ws_blueprint_id] do
      case TeamBlueprint.by_id(bp_id) do
        {:ok, bp} -> Ash.destroy!(bp)
        _ -> :ok
      end
    end

    {:noreply, socket |> WP.clear_canvas() |> assign(:ws_blueprint_id, nil) |> push_ws_state()}
  end

  def handle_event("ws_launch_team", _, socket) do
    team_name = socket.assigns.ws_team_name
    agents = socket.assigns.ws_agents

    case Observatory.Fleet.Team.create_team(team_name, strategy: String.to_existing_atom(socket.assigns.ws_strategy)) do
      {:ok, _} ->
        order = WorkshopPresets.spawn_order(agents, socket.assigns.ws_spawn_links)
        cwd = socket.assigns.ws_cwd

        launched =
          Enum.count(order, fn a ->
            match?({:ok, _}, Observatory.Fleet.Agent.launch(%{
              name: a.name, capability: a.capability, model: a.model,
              cwd: if(cwd != "", do: cwd),
              team_name: team_name, extra_instructions: a.persona
            }))
          end)

        {:noreply, flash(socket, :info, "Team #{team_name} launched with #{launched}/#{length(agents)} agents")}

      {:error, reason} ->
        {:noreply, flash(socket, :error, "Failed to create team: #{inspect(reason)}")}
    end
  end

  defp new_agent(socket, attrs) do
    count = length(socket.assigns.ws_agents)
    {x, y} = {40 + rem(count, 3) * 230, 30 + div(count, 3) * 170}
    Map.merge(%{id: socket.assigns.ws_next_id, x: x, y: y}, attrs)
  end

  defp append_agent(socket, agent) do
    socket
    |> assign(:ws_agents, socket.assigns.ws_agents ++ [agent])
    |> assign(:ws_next_id, socket.assigns.ws_next_id + 1)
    |> assign(:ws_selected_agent, agent.id)
  end

  defp merge_agent(agent, params) do
    %{agent |
      name: params["name"] || agent.name, capability: params["capability"] || agent.capability,
      model: params["model"] || agent.model, permission: params["permission"] || agent.permission,
      persona: params["persona"] || agent.persona, file_scope: params["file_scope"] || agent.file_scope,
      quality_gates: params["quality_gates"] || agent.quality_gates}
  end

  defp save_and_push(socket), do: socket |> WP.auto_save() |> push_ws_state()
  defp flash(socket, level, msg), do: Phoenix.LiveView.put_flash(socket, level, msg)

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
  defp to_int(v) when is_float(v), do: round(v)
end
