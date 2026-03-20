defmodule IchorWeb.DashboardTaskHandlers do
  @moduledoc """
  LiveView event handlers for task management functionality.
  Handles task creation, status updates, reassignment, and editing.
  """

  alias Ichor.Factory.Board

  def dispatch("update_task_status", p, s) do
    {:noreply, socket} = handle_update_task_status(p, s)
    socket
  end

  def dispatch("reassign_task", p, s) do
    {:noreply, socket} = handle_reassign_task(p, s)
    socket
  end

  def dispatch("delete_task", p, s) do
    {:noreply, socket} = handle_delete_task(p, s)
    socket
  end

  @doc """
  Handle updating a task's status (pending -> in_progress -> completed).
  """
  def handle_update_task_status(params, socket) do
    %{
      "team" => team_name,
      "task_id" => task_id,
      "status" => new_status
    } = params

    changes = %{"status" => new_status}

    case Board.update_task(team_name, task_id, changes) do
      {:ok, _updated_task} ->
        socket =
          Phoenix.LiveView.push_event(socket, "toast", %{
            message: "Task status updated to #{new_status}",
            type: "success"
          })

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @doc """
  Handle reassigning a task to a different owner.
  """
  def handle_reassign_task(params, socket) do
    %{
      "team" => team_name,
      "task_id" => task_id,
      "owner" => new_owner
    } = params

    changes = %{"owner" => new_owner}

    case Board.update_task(team_name, task_id, changes) do
      {:ok, _updated_task} ->
        socket =
          Phoenix.LiveView.push_event(socket, "toast", %{
            message: "Task reassigned to #{new_owner}",
            type: "success"
          })

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @doc """
  Handle deleting a task.
  """
  def handle_delete_task(params, socket) do
    %{
      "team" => team_name,
      "task_id" => task_id
    } = params

    case Board.delete_task(team_name, task_id) do
      :ok ->
        socket =
          Phoenix.LiveView.push_event(socket, "toast", %{
            message: "Task deleted",
            type: "success"
          })

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end
end
