defmodule ObservatoryWeb.DashboardTaskHandlers do
  @moduledoc """
  LiveView event handlers for task management functionality.
  Handles task creation, status updates, reassignment, and editing.
  """

  @doc """
  Handle creating a new task for a team.
  """
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

    case Observatory.TaskManager.create_task(team_name, attrs) do
      {:ok, task} ->
        # Broadcast task creation event
        Phoenix.PubSub.broadcast(
          Observatory.PubSub,
          "team:#{team_name}",
          {:task_created, task}
        )

        Phoenix.PubSub.broadcast(
          Observatory.PubSub,
          "teams:update",
          {:tasks_updated, team_name}
        )

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

    case Observatory.TaskManager.update_task(team_name, task_id, changes) do
      {:ok, updated_task} ->
        broadcast_task_update(team_name, updated_task)

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

    case Observatory.TaskManager.update_task(team_name, task_id, changes) do
      {:ok, updated_task} ->
        broadcast_task_update(team_name, updated_task)

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

    case Observatory.TaskManager.delete_task(team_name, task_id) do
      :ok ->
        Phoenix.PubSub.broadcast(
          Observatory.PubSub,
          "team:#{team_name}",
          {:task_deleted, task_id}
        )

        Phoenix.PubSub.broadcast(
          Observatory.PubSub,
          "teams:update",
          {:tasks_updated, team_name}
        )

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

  defp broadcast_task_update(team_name, task) do
    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "team:#{team_name}",
      {:task_updated, task}
    )

    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "teams:update",
      {:tasks_updated, team_name}
    )
  end

  defp extract_active_form(subject) do
    # Convert imperative subject to present continuous
    # "Fix bug" -> "Fixing bug"
    # "Add feature" -> "Adding feature"
    cond do
      String.starts_with?(subject, "Add ") ->
        String.replace_prefix(subject, "Add ", "Adding ")

      String.starts_with?(subject, "Fix ") ->
        String.replace_prefix(subject, "Fix ", "Fixing ")

      String.starts_with?(subject, "Update ") ->
        String.replace_prefix(subject, "Update ", "Updating ")

      String.starts_with?(subject, "Remove ") ->
        String.replace_prefix(subject, "Remove ", "Removing ")

      String.starts_with?(subject, "Create ") ->
        String.replace_prefix(subject, "Create ", "Creating ")

      String.starts_with?(subject, "Delete ") ->
        String.replace_prefix(subject, "Delete ", "Deleting ")

      String.starts_with?(subject, "Implement ") ->
        String.replace_prefix(subject, "Implement ", "Implementing ")

      true ->
        # Default: just append "ing" to first word
        subject
        |> String.split(" ", parts: 2)
        |> case do
          [first | rest] -> [first <> "ing" | rest] |> Enum.join(" ")
          _ -> subject
        end
    end
  end
end
