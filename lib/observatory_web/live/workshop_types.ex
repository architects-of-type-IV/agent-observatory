defmodule ObservatoryWeb.WorkshopTypes do
  @moduledoc """
  Event handlers for Workshop Agent Type CRUD.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Observatory.Workshop.AgentType
  alias ObservatoryWeb.WorkshopPersistence, as: WP

  def handle_event("ws_edit_type", %{"id" => id}, socket) do
    case AgentType.by_id(id) do
      {:ok, type} -> {:noreply, assign(socket, :ws_editing_type, type)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("ws_edit_type_new", _, socket) do
    {:noreply, assign(socket, :ws_editing_type, :new)}
  end

  def handle_event("ws_cancel_edit_type", _, socket) do
    {:noreply, assign(socket, :ws_editing_type, nil)}
  end

  def handle_event("ws_save_type", params, socket) do
    type_params =
      params
      |> Map.take(~w(name capability default_model default_permission
         default_persona default_file_scope default_quality_gates))
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

    result =
      case socket.assigns.ws_editing_type do
        :new -> AgentType.create(type_params)
        %AgentType{} = existing -> AgentType.update(existing, type_params)
        _ -> {:error, :no_type}
      end

    case result do
      {:ok, _} ->
        {:noreply, socket |> assign(:ws_agent_types, WP.list_agent_types()) |> assign(:ws_editing_type, nil)}

      {:error, _} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Failed to save agent type")}
    end
  end

  def handle_event("ws_delete_type", %{"id" => id}, socket) do
    case AgentType.by_id(id) do
      {:ok, type} ->
        Ash.destroy!(type)

        socket =
          if match?(%{id: ^id}, socket.assigns.ws_editing_type),
            do: assign(socket, :ws_editing_type, nil),
            else: socket

        {:noreply, assign(socket, :ws_agent_types, WP.list_agent_types())}

      _ ->
        {:noreply, socket}
    end
  end
end
