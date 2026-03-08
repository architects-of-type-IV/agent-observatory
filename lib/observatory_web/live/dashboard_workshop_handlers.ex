defmodule ObservatoryWeb.DashboardWorkshopHandlers do
  @moduledoc """
  Event handlers for the Workshop team builder canvas.
  All state is persisted through Workshop Ash resources.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Observatory.Workshop.TeamBlueprint

  # ── Blueprint persistence ─────────────────────────────────

  def handle_event("ws_save_blueprint", _params, socket) do
    socket = auto_save(socket)
    {:noreply, socket |> assign(:ws_blueprints, list_blueprints()) |> Phoenix.LiveView.put_flash(:info, "Blueprint saved")}
  end

  def handle_event("ws_load_blueprint", %{"id" => id}, socket) do
    case TeamBlueprint.by_id(id) do
      {:ok, bp} ->
        {:noreply, socket |> load_blueprint_into_assigns(bp) |> push_ws_state()}

      {:error, _} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Blueprint not found")}
    end
  end

  def handle_event("ws_delete_blueprint", %{"id" => id}, socket) do
    case TeamBlueprint.by_id(id) do
      {:ok, bp} ->
        Ash.destroy!(bp)

        socket =
          if socket.assigns[:ws_blueprint_id] == id do
            socket |> clear_ws() |> push_ws_state()
          else
            socket
          end

        {:noreply, socket |> assign(:ws_blueprints, list_blueprints()) |> Phoenix.LiveView.put_flash(:info, "Blueprint deleted")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("ws_new_blueprint", _params, socket) do
    socket
    |> clear_ws()
    |> assign(:ws_blueprint_id, nil)
    |> push_ws_state()
    |> then(&{:noreply, &1})
  end

  def handle_event("ws_list_blueprints", _params, socket) do
    {:noreply, assign(socket, :ws_blueprints, list_blueprints())}
  end

  # ── Agent CRUD ──────────────────────────────────────────────

  def handle_event("ws_add_agent", _params, socket) do
    agents = socket.assigns.ws_agents
    count = length(agents)
    col = rem(count, 3)
    row = div(count, 3)

    agent = %{
      id: socket.assigns.ws_next_id,
      name: "agent-#{count + 1}",
      capability: "builder",
      model: socket.assigns.ws_default_model,
      permission: "default",
      persona: "",
      file_scope: "",
      quality_gates: "mix compile --warnings-as-errors",
      x: 40 + col * 230,
      y: 30 + row * 170
    }

    socket
    |> assign(:ws_agents, agents ++ [agent])
    |> assign(:ws_next_id, socket.assigns.ws_next_id + 1)
    |> assign(:ws_selected_agent, agent.id)
    |> auto_save()
    |> push_ws_state()
    |> then(&{:noreply, &1})
  end

  def handle_event("ws_select_agent", %{"id" => id}, socket) do
    id = to_int(id)
    {:noreply, socket |> assign(:ws_selected_agent, id) |> push_ws_state()}
  end

  def handle_event("ws_move_agent", %{"id" => id, "x" => x, "y" => y}, socket) do
    id = to_int(id)

    agents =
      Enum.map(socket.assigns.ws_agents, fn a ->
        if a.id == id, do: %{a | x: x, y: y}, else: a
      end)

    socket
    |> assign(:ws_agents, agents)
    |> auto_save()
    |> then(&{:noreply, &1})
  end

  def handle_event("ws_update_agent", params, socket) do
    id = socket.assigns.ws_selected_agent
    if is_nil(id), do: {:noreply, socket}, else: do_update_agent(socket, id, params)
  end

  def handle_event("ws_remove_agent", _params, socket) do
    id = socket.assigns.ws_selected_agent
    if is_nil(id), do: {:noreply, socket}, else: do_remove_agent(socket, id)
  end

  # ── Links ───────────────────────────────────────────────────

  def handle_event("ws_add_spawn_link", %{"from" => from, "to" => to}, socket) do
    from = to_int(from)
    to = to_int(to)
    links = socket.assigns.ws_spawn_links

    exists? = Enum.any?(links, fn l -> l.from == from && l.to == to end)
    circular? = Enum.any?(links, fn l -> l.from == to && l.to == from end)

    if exists? || circular? do
      {:noreply, socket}
    else
      socket
      |> assign(:ws_spawn_links, links ++ [%{from: from, to: to}])
      |> auto_save()
      |> push_ws_state()
      |> then(&{:noreply, &1})
    end
  end

  def handle_event("ws_add_comm_rule", %{"from" => from, "to" => to, "policy" => policy}, socket) do
    from = to_int(from)
    to = to_int(to)
    rules = socket.assigns.ws_comm_rules

    exists? = Enum.any?(rules, fn r -> r.from == from && r.to == to && r.policy == policy end)

    if exists? do
      {:noreply, socket}
    else
      rule = %{from: from, to: to, policy: policy, via: nil}

      socket
      |> assign(:ws_comm_rules, rules ++ [rule])
      |> auto_save()
      |> push_ws_state()
      |> then(&{:noreply, &1})
    end
  end

  def handle_event("ws_add_comm_rule_manual", %{"policy" => policy}, socket) do
    agents = socket.assigns.ws_agents
    if length(agents) < 2, do: {:noreply, socket}, else: do_add_manual_rule(socket, agents, policy)
  end

  def handle_event("ws_remove_comm_rule", %{"index" => index}, socket) do
    index = to_int(index)
    rules = List.delete_at(socket.assigns.ws_comm_rules, index)

    socket
    |> assign(:ws_comm_rules, rules)
    |> auto_save()
    |> push_ws_state()
    |> then(&{:noreply, &1})
  end

  def handle_event("ws_remove_spawn_link", %{"index" => index}, socket) do
    index = to_int(index)
    links = List.delete_at(socket.assigns.ws_spawn_links, index)

    socket
    |> assign(:ws_spawn_links, links)
    |> auto_save()
    |> push_ws_state()
    |> then(&{:noreply, &1})
  end

  # ── Team config ─────────────────────────────────────────────

  def handle_event("ws_update_team", params, socket) do
    socket
    |> assign(:ws_team_name, params["name"] || socket.assigns.ws_team_name)
    |> assign(:ws_strategy, params["strategy"] || socket.assigns.ws_strategy)
    |> assign(:ws_default_model, params["default_model"] || socket.assigns.ws_default_model)
    |> assign(:ws_cwd, params["cwd"] || socket.assigns.ws_cwd)
    |> auto_save()
    |> then(&{:noreply, &1})
  end

  # ── Presets ─────────────────────────────────────────────────

  def handle_event("ws_preset", %{"name" => name}, socket) do
    socket
    |> clear_ws()
    |> apply_preset(name)
    |> auto_save()
    |> push_ws_state()
    |> then(&{:noreply, &1})
  end

  def handle_event("ws_clear", _params, socket) do
    socket = clear_ws(socket)

    # Destroy the current blueprint if it exists
    if bp_id = socket.assigns[:ws_blueprint_id] do
      case TeamBlueprint.by_id(bp_id) do
        {:ok, bp} -> Ash.destroy!(bp)
        _ -> :ok
      end
    end

    {:noreply, socket |> assign(:ws_blueprint_id, nil) |> push_ws_state()}
  end

  # ── Launch ──────────────────────────────────────────────────

  def handle_event("ws_launch_team", _params, socket) do
    team_name = socket.assigns.ws_team_name
    strategy = socket.assigns.ws_strategy
    agents = socket.assigns.ws_agents
    cwd = socket.assigns.ws_cwd

    case Observatory.Fleet.Team.create_team(team_name, strategy: String.to_existing_atom(strategy)) do
      {:ok, _} ->
        spawn_order = build_spawn_order(agents, socket.assigns.ws_spawn_links)

        results =
          Enum.map(spawn_order, fn a ->
            Observatory.Fleet.Agent.launch(%{
              name: a.name,
              capability: a.capability,
              model: a.model,
              cwd: if(cwd != "", do: cwd),
              team_name: team_name,
              extra_instructions: a.persona
            })
          end)

        launched = Enum.count(results, &match?({:ok, _}, &1))

        socket
        |> Phoenix.LiveView.put_flash(:info, "Team #{team_name} launched with #{launched}/#{length(agents)} agents")
        |> then(&{:noreply, &1})

      {:error, reason} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Failed to create team: #{inspect(reason)}")}
    end
  end

  # ── Public Helpers ─────────────────────────────────────────

  def push_ws_state(socket) do
    push_event(socket, "ws_state", %{
      agents: socket.assigns.ws_agents,
      spawn_links: socket.assigns.ws_spawn_links,
      comm_rules: socket.assigns.ws_comm_rules,
      selected_agent: socket.assigns.ws_selected_agent
    })
  end

  def list_blueprints do
    TeamBlueprint.read!() |> Ash.load!(:agent_blueprints)
  end

  # ── Private: Auto-save ─────────────────────────────────────

  defp auto_save(socket) do
    assigns = socket.assigns
    bp_id = assigns[:ws_blueprint_id]

    agent_maps = Enum.map(assigns.ws_agents, &agent_to_ash_map/1)
    link_maps = Enum.map(assigns.ws_spawn_links, &spawn_link_to_ash_map/1)
    rule_maps = Enum.map(assigns.ws_comm_rules, &comm_rule_to_ash_map/1)

    team_params = %{
      name: assigns.ws_team_name,
      strategy: assigns.ws_strategy,
      default_model: assigns.ws_default_model,
      cwd: assigns.ws_cwd,
      agent_blueprints: agent_maps,
      spawn_links: link_maps,
      comm_rules: rule_maps
    }

    case persist_blueprint(bp_id, team_params) do
      {:ok, blueprint} ->
        assign(socket, :ws_blueprint_id, blueprint.id)

      {:error, _} ->
        socket
    end
  end

  defp persist_blueprint(nil, params) do
    TeamBlueprint
    |> Ash.Changeset.for_create(:create, params)
    |> Ash.create()
  end

  defp persist_blueprint(bp_id, params) do
    case TeamBlueprint.by_id(bp_id) do
      {:ok, bp} ->
        bp
        |> Ash.Changeset.for_update(:update, params)
        |> Ash.update()

      {:error, _} ->
        persist_blueprint(nil, params)
    end
  end

  # ── Private: Ash <-> Canvas mapping ────────────────────────

  defp agent_to_ash_map(a) do
    %{
      slot: a.id,
      name: a.name,
      capability: a.capability,
      model: a.model,
      permission: a.permission,
      persona: a.persona || "",
      file_scope: a.file_scope || "",
      quality_gates: a.quality_gates || "",
      canvas_x: a.x,
      canvas_y: a.y
    }
  end

  defp ash_agent_to_canvas(a) do
    %{
      id: a.slot,
      name: a.name,
      capability: a.capability,
      model: a.model,
      permission: a.permission,
      persona: a.persona || "",
      file_scope: a.file_scope || "",
      quality_gates: a.quality_gates || "",
      x: a.canvas_x,
      y: a.canvas_y
    }
  end

  defp spawn_link_to_ash_map(l), do: %{from_slot: l.from, to_slot: l.to}
  defp ash_spawn_link_to_canvas(l), do: %{from: l.from_slot, to: l.to_slot}

  defp comm_rule_to_ash_map(r), do: %{from_slot: r.from, to_slot: r.to, policy: r.policy, via_slot: r.via}
  defp ash_comm_rule_to_canvas(r), do: %{from: r.from_slot, to: r.to_slot, policy: r.policy, via: r.via_slot}

  defp load_blueprint_into_assigns(socket, bp) do
    agents = Enum.map(bp.agent_blueprints, &ash_agent_to_canvas/1)
    links = Enum.map(bp.spawn_links, &ash_spawn_link_to_canvas/1)
    rules = Enum.map(bp.comm_rules, &ash_comm_rule_to_canvas/1)
    max_slot = agents |> Enum.map(& &1.id) |> Enum.max(fn -> 0 end)

    socket
    |> assign(:ws_blueprint_id, bp.id)
    |> assign(:ws_team_name, bp.name)
    |> assign(:ws_strategy, bp.strategy)
    |> assign(:ws_default_model, bp.default_model)
    |> assign(:ws_cwd, bp.cwd || "")
    |> assign(:ws_agents, agents)
    |> assign(:ws_spawn_links, links)
    |> assign(:ws_comm_rules, rules)
    |> assign(:ws_selected_agent, nil)
    |> assign(:ws_next_id, max_slot + 1)
  end

  # ── Private: Agent mutations ───────────────────────────────

  defp do_update_agent(socket, id, params) do
    agents =
      Enum.map(socket.assigns.ws_agents, fn a ->
        if a.id == id do
          %{a |
            name: params["name"] || a.name,
            capability: params["capability"] || a.capability,
            model: params["model"] || a.model,
            permission: params["permission"] || a.permission,
            persona: params["persona"] || a.persona,
            file_scope: params["file_scope"] || a.file_scope,
            quality_gates: params["quality_gates"] || a.quality_gates
          }
        else
          a
        end
      end)

    socket
    |> assign(:ws_agents, agents)
    |> auto_save()
    |> push_ws_state()
    |> then(&{:noreply, &1})
  end

  defp do_remove_agent(socket, id) do
    socket
    |> assign(:ws_agents, Enum.reject(socket.assigns.ws_agents, &(&1.id == id)))
    |> assign(:ws_spawn_links, Enum.reject(socket.assigns.ws_spawn_links, fn l -> l.from == id || l.to == id end))
    |> assign(:ws_comm_rules, Enum.reject(socket.assigns.ws_comm_rules, fn r -> r.from == id || r.to == id || r.via == id end))
    |> assign(:ws_selected_agent, nil)
    |> auto_save()
    |> push_ws_state()
    |> then(&{:noreply, &1})
  end

  defp do_add_manual_rule(socket, agents, policy) do
    from = hd(agents).id
    to = Enum.at(agents, 1).id
    rule = %{from: from, to: to, policy: policy, via: nil}

    socket
    |> assign(:ws_comm_rules, socket.assigns.ws_comm_rules ++ [rule])
    |> auto_save()
    |> push_ws_state()
    |> then(&{:noreply, &1})
  end

  # ── Private: Canvas state ──────────────────────────────────

  defp clear_ws(socket) do
    socket
    |> assign(:ws_agents, [])
    |> assign(:ws_spawn_links, [])
    |> assign(:ws_comm_rules, [])
    |> assign(:ws_selected_agent, nil)
    |> assign(:ws_next_id, 1)
    |> assign(:ws_team_name, "alpha")
    |> assign(:ws_strategy, "one_for_one")
    |> assign(:ws_default_model, "sonnet")
  end

  defp apply_preset(socket, "dag") do
    lead = %{id: 1, name: "lead", capability: "lead", model: "opus", permission: "default", persona: "DAG pipeline lead. Manages spawning, conflict resolution, verification, and GC.", file_scope: "", quality_gates: "mix compile --warnings-as-errors", x: 220, y: 20}
    w1 = %{id: 2, name: "worker-1", capability: "builder", model: "sonnet", permission: "default", persona: "", file_scope: "", quality_gates: "mix compile --warnings-as-errors\nmix test", x: 40, y: 200}
    w2 = %{id: 3, name: "worker-2", capability: "builder", model: "sonnet", permission: "default", persona: "", file_scope: "", quality_gates: "mix compile --warnings-as-errors\nmix test", x: 270, y: 200}
    w3 = %{id: 4, name: "worker-3", capability: "builder", model: "sonnet", permission: "default", persona: "", file_scope: "", quality_gates: "mix compile --warnings-as-errors\nmix test", x: 500, y: 200}

    socket
    |> assign(:ws_team_name, "dag-pipeline")
    |> assign(:ws_agents, [lead, w1, w2, w3])
    |> assign(:ws_next_id, 5)
    |> assign(:ws_spawn_links, [%{from: 1, to: 2}, %{from: 1, to: 3}, %{from: 1, to: 4}])
    |> assign(:ws_comm_rules, [
      %{from: 2, to: 1, policy: "allow", via: nil}, %{from: 3, to: 1, policy: "allow", via: nil}, %{from: 4, to: 1, policy: "allow", via: nil},
      %{from: 1, to: 2, policy: "allow", via: nil}, %{from: 1, to: 3, policy: "allow", via: nil}, %{from: 1, to: 4, policy: "allow", via: nil},
      %{from: 2, to: 3, policy: "deny", via: nil}, %{from: 3, to: 2, policy: "deny", via: nil},
      %{from: 2, to: 4, policy: "deny", via: nil}, %{from: 4, to: 2, policy: "deny", via: nil},
      %{from: 3, to: 4, policy: "deny", via: nil}, %{from: 4, to: 3, policy: "deny", via: nil}
    ])
  end

  defp apply_preset(socket, "solo") do
    agent = %{id: 1, name: "builder", capability: "builder", model: "opus", permission: "default", persona: "Full-stack implementation agent.", file_scope: "", quality_gates: "mix compile --warnings-as-errors", x: 200, y: 60}

    socket
    |> assign(:ws_team_name, "solo")
    |> assign(:ws_default_model, "opus")
    |> assign(:ws_agents, [agent])
    |> assign(:ws_next_id, 2)
  end

  defp apply_preset(socket, "research") do
    coord = %{id: 1, name: "coordinator", capability: "coordinator", model: "opus", permission: "default", persona: "Orchestrates research across scouts.", file_scope: "", quality_gates: "mix compile --warnings-as-errors", x: 220, y: 20}
    s1 = %{id: 2, name: "scout-api", capability: "scout", model: "haiku", permission: "default", persona: "Investigates API patterns.", file_scope: "", quality_gates: "", x: 40, y: 200}
    s2 = %{id: 3, name: "scout-db", capability: "scout", model: "haiku", permission: "default", persona: "Investigates data models.", file_scope: "", quality_gates: "", x: 270, y: 200}
    s3 = %{id: 4, name: "scout-arch", capability: "scout", model: "sonnet", permission: "default", persona: "Investigates architecture.", file_scope: "", quality_gates: "", x: 500, y: 200}

    socket
    |> assign(:ws_team_name, "research-squad")
    |> assign(:ws_strategy, "one_for_all")
    |> assign(:ws_agents, [coord, s1, s2, s3])
    |> assign(:ws_next_id, 5)
    |> assign(:ws_spawn_links, [%{from: 1, to: 2}, %{from: 1, to: 3}, %{from: 1, to: 4}])
    |> assign(:ws_comm_rules, [
      %{from: 2, to: 1, policy: "allow", via: nil}, %{from: 3, to: 1, policy: "allow", via: nil}, %{from: 4, to: 1, policy: "allow", via: nil},
      %{from: 1, to: 2, policy: "allow", via: nil}, %{from: 1, to: 3, policy: "allow", via: nil}, %{from: 1, to: 4, policy: "allow", via: nil}
    ])
  end

  defp apply_preset(socket, "review") do
    arch = %{id: 1, name: "architect", capability: "lead", model: "opus", permission: "default", persona: "Reviews designs and approves plans.", file_scope: "", quality_gates: "mix compile --warnings-as-errors", x: 320, y: 20}
    rev = %{id: 2, name: "reviewer", capability: "reviewer", model: "sonnet", permission: "default", persona: "Code review for quality and correctness.", file_scope: "", quality_gates: "", x: 80, y: 160}
    bld = %{id: 3, name: "builder", capability: "builder", model: "sonnet", permission: "default", persona: "Implements features per approved design.", file_scope: "", quality_gates: "mix compile --warnings-as-errors\nmix test", x: 320, y: 280}
    sct = %{id: 4, name: "scout", capability: "scout", model: "haiku", permission: "default", persona: "Gathers context before implementation.", file_scope: "", quality_gates: "", x: 560, y: 160}

    socket
    |> assign(:ws_team_name, "review-chain")
    |> assign(:ws_strategy, "rest_for_one")
    |> assign(:ws_agents, [arch, rev, bld, sct])
    |> assign(:ws_next_id, 5)
    |> assign(:ws_spawn_links, [%{from: 1, to: 2}, %{from: 1, to: 3}, %{from: 1, to: 4}])
    |> assign(:ws_comm_rules, [
      %{from: 4, to: 2, policy: "allow", via: nil},
      %{from: 2, to: 1, policy: "allow", via: nil},
      %{from: 3, to: 2, policy: "allow", via: nil},
      %{from: 1, to: 3, policy: "allow", via: nil},
      %{from: 3, to: 1, policy: "route", via: 2},
      %{from: 4, to: 1, policy: "deny", via: nil}
    ])
  end

  defp apply_preset(socket, _), do: socket

  # ── Private: Launch helpers ────────────────────────────────

  defp build_spawn_order(agents, spawn_links) do
    has_parent = MapSet.new(Enum.map(spawn_links, & &1.to))
    roots = Enum.filter(agents, fn a -> !MapSet.member?(has_parent, a.id) end)
    children_map = Enum.group_by(spawn_links, & &1.from, & &1.to)

    walk(roots, agents, children_map)
  end

  defp walk([], _agents, _children_map), do: []

  defp walk([root | rest], agents, children_map) do
    kids = Map.get(children_map, root.id, [])
    kid_agents = Enum.map(kids, fn kid_id -> Enum.find(agents, &(&1.id == kid_id)) end) |> Enum.filter(& &1)
    [root | walk(kid_agents ++ rest, agents, children_map)]
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
  defp to_int(v) when is_float(v), do: round(v)
end
