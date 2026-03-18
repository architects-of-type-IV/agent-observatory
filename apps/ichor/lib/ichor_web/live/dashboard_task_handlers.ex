defmodule IchorWeb.DashboardTaskHandlers do
  @moduledoc """
  LiveView event handlers for task management functionality.
  Handles task creation, status updates, reassignment, and editing.
  """

  alias Ichor.Tasks.Board

  def dispatch("create_task", p, s) do
    {:noreply, socket} = handle_create_task(p, s)
    Phoenix.Component.assign(socket, :show_create_task_modal, false)
  end

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

  def handle_create_task(params, socket) do
    %{
      "team" => team_name,
      "subject" => subject,
      "description" => description
    } = params

    attrs = %{
      "subject" => subject,
      "description" => description,
      "activeForm" => params["activeForm"] || extract_active_form(subject),
      "status" => params["status"] || "pending",
      "owner" => params["owner"] || "",
      "blocks" => params["blocks"] || [],
      "blockedBy" => params["blockedBy"] || []
    }

    case Board.create_task(team_name, attrs) do
      {:ok, _task} ->
        socket =
          Phoenix.LiveView.push_event(socket, "toast", %{
            message: "Task created: #{subject}",
            type: "success"
          })

        {:noreply, socket}

      {:error, _reason} ->
        socket =
          Phoenix.LiveView.push_event(socket, "toast", %{
            message: "Failed to create task",
            type: "error"
          })

        {:noreply, socket}
    end
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

  # ═══════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════
  @verb_prefixes [
    {"Add ", "Adding "},
    {"Fix ", "Fixing "},
    {"Update ", "Updating "},
    {"Remove ", "Removing "},
    {"Create ", "Creating "},
    {"Delete ", "Deleting "},
    {"Implement ", "Implementing "}
  ]

  defp extract_active_form(subject) do
    case Enum.find(@verb_prefixes, fn {prefix, _} -> String.starts_with?(subject, prefix) end) do
      {prefix, replacement} -> String.replace_prefix(subject, prefix, replacement)
      nil -> gerundify(subject)
    end
  end

  defp gerundify(subject) do
    case String.split(subject, " ", parts: 2) do
      [first | rest] -> Enum.join([first <> "ing" | rest], " ")
      _ -> subject
    end
  end
end
