defmodule Ichor.AgentTools.Inbox do
  @moduledoc """
  Message exchange tools for agents. Check, acknowledge, and send messages.
  Routes through Fleet code interfaces for consistency.
  """
  use Ash.Resource, domain: Ichor.AgentTools

  alias Ichor.Control
  alias Ichor.MessageRouter

  actions do
    action :check_inbox, {:array, :map} do
      description(
        "Check for pending messages in your Ichor inbox. Returns unread messages from the dashboard or other agents."
      )

      argument :session_id, :string do
        allow_nil?(false)
        description("Your agent session ID")
      end

      run(fn input, _context ->
        session_id = input.arguments.session_id

        case Control.get_unread(session_id) do
          {:ok, messages} -> {:ok, messages}
          {:error, _} -> {:ok, []}
        end
      end)
    end

    action :acknowledge_message, :map do
      description("Mark a message as read after processing it.")

      argument :session_id, :string do
        allow_nil?(false)
        description("Your agent session ID")
      end

      argument :message_id, :string do
        allow_nil?(false)
        description("The ID of the message to acknowledge")
      end

      run(fn input, _context ->
        Control.mark_read(input.arguments.session_id, input.arguments.message_id)
      end)
    end

    action :send_message, :map do
      description("Send a message to another agent or back to the Ichor dashboard.")

      argument :from_session_id, :string do
        allow_nil?(false)
        description("Your agent session ID (the sender)")
      end

      argument :to_session_id, :string do
        allow_nil?(false)
        description("The recipient agent's session ID")
      end

      argument :content, :string do
        allow_nil?(false)
        description("The message content")
      end

      run(fn input, _context ->
        case MessageRouter.send(%{
               from: input.arguments.from_session_id,
               to: input.arguments.to_session_id,
               content: input.arguments.content,
               type: :message
             }) do
          {:ok, result} ->
            {:ok,
             %{
               "status" => result.status,
               "to" => result.to,
               "delivered" => result.delivered,
               "via" => nil,
               "error" => nil
             }}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    end
  end
end
