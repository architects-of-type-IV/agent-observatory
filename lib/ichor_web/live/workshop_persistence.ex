defmodule IchorWeb.WorkshopPersistence do
  @moduledoc """
  Ash persistence layer for the Workshop canvas.
  Handles auto-save, team CRUD events, and Ash <-> canvas mapping.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Ichor.Workshop.{AgentType, CanvasState, Team, TeamMember}

  @spec list_teams() :: [map()]
  def list_teams, do: Team.list_all!()

  @spec list_agent_types() :: [map()]
  def list_agent_types, do: AgentType.sorted!()

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
    |> assign_workshop_state(CanvasState.clear(socket.assigns))
  end

  def handle_event("ws_save_team", _, socket) do
    socket = auto_save(socket)

    {:noreply, socket |> assign(:ws_teams, list_teams()) |> flash(:info, "Blueprint saved")}
  end

  def handle_event("ws_load_team", %{"id" => id}, socket) do
    case load_team(socket.assigns, id) do
      {:ok, state} -> {:noreply, socket |> assign_workshop_state(state) |> push_ws_state()}
      {:error, _} -> {:noreply, flash(socket, :error, "Blueprint not found")}
    end
  end

  def handle_event("ws_delete_team", %{"id" => id}, socket) do
    case delete_team(id) do
      :ok ->
        socket =
          if socket.assigns[:ws_team_id] == id,
            do: socket |> clear_canvas() |> push_ws_state(),
            else: socket

        {:noreply, socket |> assign(:ws_teams, list_teams()) |> flash(:info, "Blueprint deleted")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("ws_new_team", _, socket) do
    {:noreply, socket |> clear_canvas() |> assign(:ws_team_id, nil) |> push_ws_state()}
  end

  def handle_event("ws_list_teams", _, socket) do
    {:noreply, assign(socket, :ws_teams, list_teams())}
  end

  @spec auto_save(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def auto_save(socket) do
    case save_team(socket.assigns[:ws_team_id], socket.assigns) do
      {:ok, bp} ->
        socket |> assign(:ws_team_id, bp.id) |> assign(:ws_teams, list_teams())

      {:error, _} ->
        socket
    end
  end

  defp save_team(nil, state) do
    with {:ok, team} <- Team.create(CanvasState.to_persistence_params(state)),
         :ok <- TeamMember.sync_from_workshop_state(team, state) do
      {:ok, team}
    end
  end

  defp save_team(id, state) do
    params = CanvasState.to_persistence_params(state)

    case Team.by_id(id) do
      {:ok, team} ->
        with {:ok, updated} <- Team.update(team, params),
             :ok <- TeamMember.sync_from_workshop_state(updated, state) do
          {:ok, updated}
        end

      {:error, _} ->
        save_team(nil, state)
    end
  end

  defp load_team(state, id) do
    with {:ok, team} <- Team.by_id(id) do
      {:ok, CanvasState.apply_team(state, team)}
    end
  end

  defp delete_team(id) do
    with {:ok, team} <- Team.by_id(id) do
      Team.destroy(team)
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
    |> assign(:ws_team_id, state.ws_team_id)
  end
end
