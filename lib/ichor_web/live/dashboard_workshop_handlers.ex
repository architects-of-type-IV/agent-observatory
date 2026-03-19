defmodule IchorWeb.DashboardWorkshopHandlers do
  @moduledoc """
  Canvas event handlers for the Workshop team builder.
  Blueprint CRUD in WorkshopPersistence. Types in WorkshopTypes.
  Presets in WorkshopPresets.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Ichor.Control
  alias Ichor.Fleet.Lifecycle
  alias Ichor.Workshop.BlueprintState
  alias Ichor.Workshop.Persistence, as: WorkshopPersistence
  alias Ichor.Workshop.Presets
  alias Ichor.Workshop.TeamSpecBuilder
  alias IchorWeb.WorkshopPersistence, as: WP
  alias Phoenix.LiveView

  def list_blueprints, do: Control.list_blueprints()
  def list_agent_types, do: Control.list_agent_types()
  defdelegate push_ws_state(socket), to: WP

  def handle_event("ws_add_agent", _, socket) do
    state =
      BlueprintState.add_agent(socket.assigns, %{
        name: "agent-#{length(socket.assigns.ws_agents) + 1}",
        capability: "builder",
        model: socket.assigns.ws_default_model,
        permission: "default",
        persona: "",
        file_scope: "",
        quality_gates: "mix compile --warnings-as-errors"
      })

    {:noreply, socket |> assign_workshop_state(state) |> save_and_push()}
  end

  def handle_event("ws_add_agent_from_type", %{"id" => id}, socket) do
    case Control.agent_type(id) do
      {:ok, type} ->
        state =
          socket.assigns
          |> BlueprintState.add_agent(%{
            name: "#{type.name}-#{length(socket.assigns.ws_agents) + 1}",
            capability: type.capability,
            model: type.default_model,
            permission: type.default_permission,
            persona: type.default_persona || "",
            file_scope: type.default_file_scope || "",
            quality_gates: type.default_quality_gates || ""
          })

        {:noreply, socket |> assign_workshop_state(state) |> save_and_push()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("ws_select_agent", %{"id" => id}, socket) do
    state = BlueprintState.select_agent(socket.assigns, to_int(id))
    {:noreply, socket |> assign_workshop_state(state) |> push_ws_state()}
  end

  def handle_event("ws_move_agent", %{"id" => id, "x" => x, "y" => y}, socket) do
    state = BlueprintState.move_agent(socket.assigns, to_int(id), to_int(x), to_int(y))
    {:noreply, socket |> assign_workshop_state(state) |> WP.auto_save()}
  end

  def handle_event("ws_update_agent", params, socket) do
    case socket.assigns.ws_selected_agent do
      nil ->
        {:noreply, socket}

      id ->
        {:noreply,
         socket
         |> assign_workshop_state(BlueprintState.update_agent(socket.assigns, id, params))
         |> save_and_push()}
    end
  end

  def handle_event("ws_remove_agent", _, socket) do
    case socket.assigns.ws_selected_agent do
      nil ->
        {:noreply, socket}

      id ->
        {:noreply,
         socket
         |> assign_workshop_state(BlueprintState.remove_agent(socket.assigns, id))
         |> save_and_push()}
    end
  end

  def handle_event("ws_add_spawn_link", %{"from" => from, "to" => to}, socket) do
    state = BlueprintState.add_spawn_link(socket.assigns, to_int(from), to_int(to))
    {:noreply, socket |> assign_workshop_state(state) |> save_and_push()}
  end

  def handle_event("ws_add_comm_rule", %{"from" => from, "to" => to, "policy" => policy}, socket) do
    state = BlueprintState.add_comm_rule(socket.assigns, to_int(from), to_int(to), policy)
    {:noreply, socket |> assign_workshop_state(state) |> save_and_push()}
  end

  def handle_event("ws_remove_spawn_link", %{"index" => idx}, socket) do
    state = BlueprintState.remove_spawn_link(socket.assigns, to_int(idx))
    {:noreply, socket |> assign_workshop_state(state) |> save_and_push()}
  end

  def handle_event("ws_remove_comm_rule", %{"index" => idx}, socket) do
    state = BlueprintState.remove_comm_rule(socket.assigns, to_int(idx))
    {:noreply, socket |> assign_workshop_state(state) |> save_and_push()}
  end

  def handle_event("ws_update_team", params, socket) do
    state = BlueprintState.update_team(socket.assigns, params)
    {:noreply, socket |> assign_workshop_state(state) |> WP.auto_save()}
  end

  def handle_event("ws_preset", %{"name" => name}, socket) do
    {:noreply, socket |> WP.clear_canvas() |> apply_preset(name) |> save_and_push()}
  end

  def handle_event("ws_clear", _, socket) do
    if bp_id = socket.assigns[:ws_blueprint_id] do
      _ = WorkshopPersistence.delete_blueprint(bp_id)
    end

    {:noreply, socket |> WP.clear_canvas() |> assign(:ws_blueprint_id, nil) |> push_ws_state()}
  end

  def handle_event("ws_launch_team", _, socket) do
    case launch_team(socket.assigns) do
      {:ok, result} ->
        {:noreply,
         flash(
           socket,
           :info,
           "Team #{result.team_name} launched with #{result.launched}/#{result.total} agents"
         )}

      {:error, reason} ->
        {:noreply, flash(socket, :error, "Failed to launch team: #{inspect(reason)}")}
    end
  end

  defp launch_team(state) do
    spec = TeamSpecBuilder.build_from_state(state)

    with {:ok, session} <- Lifecycle.launch_team(spec) do
      {:ok,
       %{
         team_name: spec.team_name,
         session: session,
         launched: length(spec.agents),
         total: length(spec.agents)
       }}
    end
  end

  defp apply_preset(socket, name) do
    state = Presets.apply(socket.assigns, name)

    socket
    |> assign(:ws_team_name, state.ws_team_name)
    |> assign(:ws_strategy, state.ws_strategy)
    |> assign(:ws_default_model, state.ws_default_model)
    |> assign(:ws_agents, state.ws_agents)
    |> assign(:ws_next_id, state.ws_next_id)
    |> assign(:ws_spawn_links, state.ws_spawn_links)
    |> assign(:ws_comm_rules, state.ws_comm_rules)
  end

  defp save_and_push(socket), do: socket |> WP.auto_save() |> push_ws_state()
  defp flash(socket, level, msg), do: LiveView.put_flash(socket, level, msg)

  defp assign_workshop_state(socket, state) do
    socket
    |> assign(:ws_agents, state.ws_agents)
    |> assign(:ws_spawn_links, state.ws_spawn_links)
    |> assign(:ws_comm_rules, state.ws_comm_rules)
    |> assign(:ws_selected_agent, state.ws_selected_agent)
    |> assign(:ws_next_id, state.ws_next_id)
    |> assign(:ws_team_name, state.ws_team_name)
    |> assign(:ws_strategy, state.ws_strategy)
    |> assign(:ws_default_model, state.ws_default_model)
    |> assign(:ws_cwd, state.ws_cwd)
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
  defp to_int(v) when is_float(v), do: round(v)
end
