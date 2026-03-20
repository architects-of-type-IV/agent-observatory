defmodule IchorWeb.WorkshopTypes do
  @moduledoc """
  Event handlers for Workshop Agent Type CRUD.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Ichor.Workshop.AgentType

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
    type_params = %{
      name: params["name"],
      capability: params["capability"],
      default_model: params["default_model"],
      default_permission: params["default_permission"],
      default_persona: params["default_persona"],
      default_file_scope: params["default_file_scope"],
      default_quality_gates: params["default_quality_gates"]
    }

    result =
      case socket.assigns.ws_editing_type do
        :new -> AgentType.create(type_params)
        %{__struct__: _} = existing -> AgentType.update(existing, type_params)
        _ -> {:error, :no_type}
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:ws_agent_types, AgentType.sorted!())
         |> assign(:ws_editing_type, nil)}

      {:error, _} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Failed to save agent type")}
    end
  end

  def handle_event("ws_delete_type", %{"id" => id}, socket) do
    case AgentType.by_id(id) do
      {:ok, type} ->
        :ok = AgentType.destroy(type)

        socket =
          if match?(%{id: ^id}, socket.assigns.ws_editing_type),
            do: assign(socket, :ws_editing_type, nil),
            else: socket

        {:noreply, assign(socket, :ws_agent_types, AgentType.sorted!())}

      _ ->
        {:noreply, socket}
    end
  end
end
