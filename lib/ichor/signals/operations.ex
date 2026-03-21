defmodule Ichor.Signals.Operations do
  @moduledoc """
  Action-only signal and messaging surface for agent and operator communication.
  """

  use Ash.Resource, domain: Ichor.SignalBus

  alias Ichor.Infrastructure.AgentProcess
  alias Ichor.Signals.Bus
  alias Ichor.Signals.EventStream

  actions do
    action :check_operator_inbox, {:array, :map} do
      description("Read unread messages addressed to the operator mailbox.")

      run(fn _input, _context ->
        messages =
          if AgentProcess.alive?("operator") do
            AgentProcess.get_unread("operator")
            |> Enum.map(fn message ->
              %{
                "from" => message[:from] || message["from"],
                "content" => message[:content] || message["content"],
                "timestamp" => message[:timestamp] || message["timestamp"]
              }
            end)
          else
            []
          end

        {:ok, messages}
      end)
    end

    action :check_inbox, {:array, :map} do
      description("Check for pending messages in an agent inbox.")

      argument(:session_id, :string, allow_nil?: false)

      run(fn input, _context ->
        messages =
          if AgentProcess.alive?(input.arguments.session_id) do
            AgentProcess.get_unread(input.arguments.session_id)
          else
            []
          end

        {:ok, messages}
      end)
    end

    action :acknowledge_message, :map do
      description("Mark a pulled inbox message as acknowledged.")

      argument(:session_id, :string, allow_nil?: false)
      argument(:message_id, :string, allow_nil?: false)

      run(fn input, _context ->
        {:ok,
         %{
           "status" => "acknowledged",
           "session_id" => input.arguments.session_id,
           "message_id" => input.arguments.message_id
         }}
      end)
    end

    action :agent_send_message, :map do
      description("Send a direct message from one agent session to another.")

      argument(:from_session_id, :string, allow_nil?: false)
      argument(:to_session_id, :string, allow_nil?: false)
      argument(:content, :string, allow_nil?: false)

      run(fn input, _context ->
        case Bus.send(%{
               from: input.arguments.from_session_id,
               to: input.arguments.to_session_id,
               content: input.arguments.content,
               type: :message,
               transport: :mcp
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

    action :recent_messages, {:array, :map} do
      description("Get recent inter-agent/operator messages.")

      argument(:limit, :integer, allow_nil?: false, default: 20)

      run(fn input, _context ->
        {:ok,
         Bus.recent_messages(input.arguments.limit)
         |> Enum.map(fn message ->
           %{
             "id" => message.id,
             "from" => message.from,
             "to" => message.to,
             "content" => String.slice(message.content || "", 0, 500),
             "type" => message.type,
             "timestamp" => message.timestamp
           }
         end)}
      end)
    end

    action :operator_send_message, :map do
      description("Send a message to an agent or team as the operator.")

      argument(:to, :string, allow_nil?: false)
      argument(:content, :string, allow_nil?: false)

      run(fn input, _context ->
        with {:ok, result} <-
               Bus.send(%{
                 from: "archon",
                 to: input.arguments.to,
                 content: input.arguments.content
               }) do
          {:ok,
           %{
             "status" => result.status,
             "to" => result.to,
             "delivered" => result.delivered
           }}
        end
      end)
    end

    action :agent_events, {:array, :map} do
      description("Read recent raw event stream entries for an agent session.")

      argument(:agent_id, :string, allow_nil?: false)
      argument(:limit, :integer, allow_nil?: false, default: 30)

      run(fn input, _context ->
        limit = input.arguments.limit

        {:ok,
         EventStream.events_for_session(input.arguments.agent_id)
         |> Enum.take(limit)
         |> Enum.map(fn event ->
           %{
             "type" => event.hook_event_type,
             "tool" => event.tool_name,
             "at" => event.inserted_at,
             "summary" => event.summary,
             "cwd" => event.cwd
           }
         end)}
      end)
    end
  end
end
