defmodule Observatory.AgentTools.Inbox do
  @moduledoc """
  Message exchange tools for agents. Check, acknowledge, and send messages.
  """
  use Ash.Resource, domain: Observatory.AgentTools

  alias Observatory.Fleet.AgentProcess
  alias Observatory.Mailbox

  actions do
    action :check_inbox, {:array, :map} do
      description "Check for pending messages in your Observatory inbox. Returns unread messages from the dashboard or other agents."

      argument :session_id, :string do
        allow_nil? false
        description "Your agent session ID"
      end

      run fn input, _context ->
        session_id = input.arguments.session_id

        process_messages =
          if AgentProcess.alive?(session_id) do
            AgentProcess.get_unread(session_id)
            |> Enum.map(fn msg ->
              %{
                "id" => msg[:id] || Ecto.UUID.generate(),
                "from" => msg[:from] || "system",
                "content" => msg[:content] || inspect(msg),
                "type" => to_string(msg[:type] || :message),
                "timestamp" => DateTime.to_iso8601(msg[:timestamp] || DateTime.utc_now())
              }
            end)
          else
            []
          end

        mailbox_messages =
          Mailbox.get_messages(session_id)
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

        {:ok, process_messages ++ mailbox_messages}
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
        Mailbox.mark_read(session_id, message_id)
        cleanup_command_queue(session_id, message_id)
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

        case Observatory.Fleet.Agent.send_message(to, content, %{from: from}) do
          {:ok, _result} ->
            {:ok, %{"status" => "sent", "to" => to, "delivered" => 1, "via" => "fleet"}}

          {:error, _reason} ->
            case Observatory.Gateway.Router.broadcast("agent:#{to}", %{content: content, from: from}) do
              {:ok, delivered} when delivered > 0 ->
                {:ok, %{"status" => "sent", "to" => to, "delivered" => delivered}}

              {:ok, 0} ->
                {:ok, %{"status" => "no_recipients", "to" => to, "delivered" => 0,
                  "error" => "No delivery channel found for #{to}. Agent may not be registered."}}

              {:error, reason} ->
                {:error, "Failed to send message: #{inspect(reason)}"}
            end
        end
      end
    end
  end

  defp cleanup_command_queue(session_id, message_id) do
    inbox_dir = Path.expand("~/.claude/inbox/#{session_id}")

    if File.dir?(inbox_dir) do
      case File.ls(inbox_dir) do
        {:ok, files} ->
          Enum.each(files, fn file ->
            file_path = Path.join(inbox_dir, file)

            with {:ok, content} <- File.read(file_path),
                 {:ok, %{"id" => ^message_id}} <- Jason.decode(content) do
              File.rm(file_path)
            end
          end)

        _ -> :ok
      end
    end
  end
end
