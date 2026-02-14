defmodule Observatory.AgentTools.Inbox do
  @moduledoc """
  Ash Resource exposing agent inbox operations as MCP tools.
  Uses generic actions that delegate to the existing Mailbox GenServer.
  """
  use Ash.Resource, domain: Observatory.AgentTools

  actions do
    action :check_inbox, {:array, :map} do
      description "Check for pending messages in your Observatory inbox. Returns unread messages from the dashboard or other agents."

      argument :session_id, :string do
        allow_nil? false
        description "Your agent session ID"
      end

      run fn input, _context ->
        session_id = input.arguments.session_id
        messages = Observatory.Mailbox.get_messages(session_id)

        unread =
          messages
          |> Enum.filter(fn msg -> !msg.read end)
          |> Enum.map(fn msg ->
            %{
              "id" => msg.id,
              "from" => msg.from,
              "content" => msg.content,
              "type" => to_string(msg.type),
              "timestamp" => DateTime.to_iso8601(msg.timestamp)
            }
          end)

        {:ok, unread}
      end
    end

    action :acknowledge_message, :map do
      description "Mark a message as read after processing it."

      argument :session_id, :string do
        allow_nil? false
        description "Your agent session ID"
      end

      argument :message_id, :string do
        allow_nil? false
        description "The ID of the message to acknowledge"
      end

      run fn input, _context ->
        session_id = input.arguments.session_id
        message_id = input.arguments.message_id
        Observatory.Mailbox.mark_read(session_id, message_id)
        {:ok, %{"status" => "acknowledged", "message_id" => message_id}}
      end
    end

    action :send_message, :map do
      description "Send a message to another agent or back to the Observatory dashboard."

      argument :from_session_id, :string do
        allow_nil? false
        description "Your agent session ID (the sender)"
      end

      argument :to_session_id, :string do
        allow_nil? false
        description "The recipient agent's session ID"
      end

      argument :content, :string do
        allow_nil? false
        description "The message content"
      end

      run fn input, _context ->
        from = input.arguments.from_session_id
        to = input.arguments.to_session_id
        content = input.arguments.content

        case Observatory.Mailbox.send_message(to, from, content, type: :text) do
          {:ok, message} ->
            {:ok, %{"status" => "sent", "message_id" => message.id, "to" => to}}

          {:error, reason} ->
            {:error, "Failed to send message: #{inspect(reason)}"}
        end
      end
    end

    action :get_tasks, {:array, :map} do
      description "Get your assigned tasks from the Observatory task board."

      argument :session_id, :string do
        allow_nil? false
        description "Your agent session ID"
      end

      argument :team_name, :string do
        allow_nil? true
        description "Filter tasks by team name (optional)"
      end

      run fn input, _context ->
        session_id = input.arguments.session_id
        team_name = input.arguments[:team_name]

        tasks =
          if team_name do
            Observatory.TaskManager.list_tasks(team_name)
          else
            []
          end

        my_tasks =
          tasks
          |> Enum.filter(fn task ->
            task["owner"] == session_id || task["owner"] == nil
          end)
          |> Enum.map(fn task ->
            %{
              "id" => task["id"],
              "subject" => task["subject"],
              "status" => task["status"],
              "owner" => task["owner"],
              "description" => task["description"]
            }
          end)

        {:ok, my_tasks}
      end
    end

    action :update_task_status, :map do
      description "Update the status of a task you are working on."

      argument :team_name, :string do
        allow_nil? false
        description "The team name the task belongs to"
      end

      argument :task_id, :string do
        allow_nil? false
        description "The task ID to update"
      end

      argument :status, :string do
        allow_nil? false
        description "New status: pending, in_progress, or completed"
      end

      run fn input, _context ->
        team = input.arguments.team_name
        task_id = input.arguments.task_id
        status = input.arguments.status

        case Observatory.TaskManager.update_task(team, task_id, %{"status" => status}) do
          {:ok, task} ->
            {:ok, %{"status" => "updated", "task_id" => task_id, "new_status" => task["status"] || status}}

          {:error, reason} ->
            {:error, "Failed to update task: #{inspect(reason)}"}
        end
      end
    end
  end
end
