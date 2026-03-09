defmodule Ichor.AgentTools.Inbox do
  @moduledoc """
  Message exchange tools for agents. Check, acknowledge, and send messages.
  Routes through Fleet code interfaces for consistency.
  """
  use Ash.Resource, domain: Ichor.AgentTools

  alias Ichor.Fleet.Agent, as: FleetAgent

  actions do
    action :check_inbox, {:array, :map} do
      description "Check for pending messages in your Ichor inbox. Returns unread messages from the dashboard or other agents."

      argument :session_id, :string do
        allow_nil? false
        description "Your agent session ID"
      end

      run fn input, _context ->
        session_id = input.arguments.session_id

        case FleetAgent.get_unread(session_id) do
          {:ok, messages} -> {:ok, messages}
          {:error, _} -> {:ok, []}
        end
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
        FleetAgent.mark_read(input.arguments.session_id, input.arguments.message_id)
      end
    end

    action :send_message, :map do
      description "Send a message to another agent or back to the Ichor dashboard."

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

        case FleetAgent.send_message(to, content, %{from: from}) do
          {:ok, _result} ->
            {:ok, %{"status" => "sent", "to" => to, "delivered" => 1, "via" => "fleet"}}

          {:error, _reason} ->
            case Ichor.Gateway.Router.broadcast("agent:#{to}", %{content: content, from: from}) do
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
end
