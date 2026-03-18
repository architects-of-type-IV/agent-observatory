defmodule IchorWeb.WorkshopPersistence do
  @moduledoc """
  Ash persistence layer for the Workshop canvas.
  Handles auto-save, blueprint CRUD events, and Ash <-> canvas mapping.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Ichor.Workshop.{AgentType, TeamBlueprint}

  # ── Public Queries ─────────────────────────────────────────

  @spec list_blueprints() :: [map()]
  def list_blueprints, do: TeamBlueprint.read!() |> Ash.load!(:agent_blueprints)

  @spec list_agent_types() :: [map()]
  def list_agent_types, do: AgentType.sorted!()

  # ── Push Canvas State ──────────────────────────────────────

  @spec push_ws_state(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def push_ws_state(socket) do
    push_event(socket, "ws_state", %{
      agents: socket.assigns.ws_agents,
      spawn_links: socket.assigns.ws_spawn_links,
      comm_rules: socket.assigns.ws_comm_rules,
      selected_agent: socket.assigns.ws_selected_agent
    })
  end

  # ── Clear Canvas ───────────────────────────────────────────

  @spec clear_canvas(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def clear_canvas(socket) do
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

  # ── Blueprint Events ───────────────────────────────────────

  def handle_event("ws_save_blueprint", _, socket) do
    socket = auto_save(socket)

    {:noreply,
     socket |> assign(:ws_blueprints, list_blueprints()) |> flash(:info, "Blueprint saved")}
  end

  def handle_event("ws_load_blueprint", %{"id" => id}, socket) do
    case TeamBlueprint.by_id(id) do
      {:ok, bp} -> {:noreply, socket |> load_blueprint(bp) |> push_ws_state()}
      {:error, _} -> {:noreply, flash(socket, :error, "Blueprint not found")}
    end
  end

  def handle_event("ws_delete_blueprint", %{"id" => id}, socket) do
    case TeamBlueprint.by_id(id) do
      {:ok, bp} ->
        Ash.destroy!(bp)

        socket =
          if socket.assigns[:ws_blueprint_id] == id,
            do: socket |> clear_canvas() |> push_ws_state(),
            else: socket

        {:noreply,
         socket |> assign(:ws_blueprints, list_blueprints()) |> flash(:info, "Blueprint deleted")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("ws_new_blueprint", _, socket) do
    {:noreply, socket |> clear_canvas() |> assign(:ws_blueprint_id, nil) |> push_ws_state()}
  end

  def handle_event("ws_list_blueprints", _, socket) do
    {:noreply, assign(socket, :ws_blueprints, list_blueprints())}
  end

  # ── Auto-Save ──────────────────────────────────────────────

  @spec auto_save(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def auto_save(socket) do
    assigns = socket.assigns

    team_params = %{
      name: assigns.ws_team_name,
      strategy: assigns.ws_strategy,
      default_model: assigns.ws_default_model,
      cwd: assigns.ws_cwd,
      agent_blueprints: Enum.map(assigns.ws_agents, &agent_to_ash/1),
      spawn_links: Enum.map(assigns.ws_spawn_links, &link_to_ash/1),
      comm_rules: Enum.map(assigns.ws_comm_rules, &rule_to_ash/1)
    }

    case persist(assigns[:ws_blueprint_id], team_params) do
      {:ok, bp} ->
        socket |> assign(:ws_blueprint_id, bp.id) |> assign(:ws_blueprints, list_blueprints())

      {:error, _} ->
        socket
    end
  end

  # ── Blueprint Load ─────────────────────────────────────────

  @spec load_blueprint(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def load_blueprint(socket, bp) do
    agents = Enum.map(bp.agent_blueprints, &ash_to_agent/1)
    links = Enum.map(bp.spawn_links, &ash_to_link/1)
    rules = Enum.map(bp.comm_rules, &ash_to_rule/1)
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

  # ── Private ────────────────────────────────────────────────

  defp persist(nil, params) do
    TeamBlueprint |> Ash.Changeset.for_create(:create, params) |> Ash.create()
  end

  defp persist(bp_id, params) do
    case TeamBlueprint.by_id(bp_id) do
      {:ok, bp} -> bp |> Ash.Changeset.for_update(:update, params) |> Ash.update()
      {:error, _} -> persist(nil, params)
    end
  end

  defp flash(socket, level, msg), do: Phoenix.LiveView.put_flash(socket, level, msg)

  defp agent_to_ash(a) do
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

  defp ash_to_agent(a) do
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

  defp link_to_ash(l), do: %{from_slot: l.from, to_slot: l.to}
  defp ash_to_link(l), do: %{from: l.from_slot, to: l.to_slot}
  defp rule_to_ash(r), do: %{from_slot: r.from, to_slot: r.to, policy: r.policy, via_slot: r.via}
  defp ash_to_rule(r), do: %{from: r.from_slot, to: r.to_slot, policy: r.policy, via: r.via_slot}
end
