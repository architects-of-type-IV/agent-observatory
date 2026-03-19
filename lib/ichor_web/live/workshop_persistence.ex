defmodule IchorWeb.WorkshopPersistence do
  @moduledoc """
  Ash persistence layer for the Workshop canvas.
  Handles auto-save, blueprint CRUD events, and Ash <-> canvas mapping.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Ichor.Workshop
  alias Ichor.Workshop.BlueprintState
  alias Ichor.Workshop.Persistence

  @spec list_blueprints() :: [map()]
  def list_blueprints, do: Workshop.list_blueprints()

  @spec list_agent_types() :: [map()]
  def list_agent_types, do: Workshop.list_agent_types()

  @spec push_ws_state(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def push_ws_state(socket) do
    push_event(socket, "ws_state", %{
      agents: socket.assigns.ws_agents,
      spawn_links: socket.assigns.ws_spawn_links,
      comm_rules: socket.assigns.ws_comm_rules,
      selected_agent: socket.assigns.ws_selected_agent
    })
  end

  @spec clear_canvas(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def clear_canvas(socket) do
    socket
    |> assign_workshop_state(BlueprintState.clear(socket.assigns))
  end

  def handle_event("ws_save_blueprint", _, socket) do
    socket = auto_save(socket)

    {:noreply,
     socket |> assign(:ws_blueprints, list_blueprints()) |> flash(:info, "Blueprint saved")}
  end

  def handle_event("ws_load_blueprint", %{"id" => id}, socket) do
    case Persistence.load_blueprint(socket.assigns, id) do
      {:ok, state} -> {:noreply, socket |> assign_workshop_state(state) |> push_ws_state()}
      {:error, _} -> {:noreply, flash(socket, :error, "Blueprint not found")}
    end
  end

  def handle_event("ws_delete_blueprint", %{"id" => id}, socket) do
    case Persistence.delete_blueprint(id) do
      :ok ->
        socket =
          if socket.assigns[:ws_blueprint_id] == id,
            do: socket |> clear_canvas() |> push_ws_state(),
            else: socket

        {:noreply,
         socket |> assign(:ws_blueprints, list_blueprints()) |> flash(:info, "Blueprint deleted")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("ws_new_blueprint", _, socket) do
    {:noreply, socket |> clear_canvas() |> assign(:ws_blueprint_id, nil) |> push_ws_state()}
  end

  def handle_event("ws_list_blueprints", _, socket) do
    {:noreply, assign(socket, :ws_blueprints, list_blueprints())}
  end

  @spec auto_save(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def auto_save(socket) do
    case Persistence.save_blueprint(socket.assigns[:ws_blueprint_id], socket.assigns) do
      {:ok, bp} ->
        socket |> assign(:ws_blueprint_id, bp.id) |> assign(:ws_blueprints, list_blueprints())

      {:error, _} ->
        socket
    end
  end

  defp flash(socket, level, msg), do: Phoenix.LiveView.put_flash(socket, level, msg)

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
    |> assign(:ws_blueprint_id, state.ws_blueprint_id)
  end
end
