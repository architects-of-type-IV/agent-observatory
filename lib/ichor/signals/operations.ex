defmodule Ichor.Signals.Operations do
  @moduledoc """
  Action-only signal and messaging surface for agent and operator communication.
  """

  use Ash.Resource, domain: Ichor.SignalBus

  alias Ichor.Observability.Message
  alias Ichor.Signals.Bus
  alias Ichor.Signals.EventStream
  alias Ichor.Workshop.Agent

  actions do
    action :check_inbox, {:array, :map} do
      description("Check for pending messages in an agent inbox.")

      argument(:session_id, :string, allow_nil?: false)

      run(fn input, _context ->
        case Agent.get_unread(input.arguments.session_id) do
          {:ok, messages} -> {:ok, messages}
          {:error, _reason} -> {:ok, []}
        end
      end)
    end

    action :acknowledge_message, :map do
      description("Mark a pulled inbox message as acknowledged.")

      argument(:session_id, :string, allow_nil?: false)
      argument(:message_id, :string, allow_nil?: false)

      run(fn input, _context ->
        Agent.mark_read(input.arguments.session_id, input.arguments.message_id)
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
        limit = input.arguments[:limit] || 20

        {:ok,
         Message.recent!()
         |> Enum.take(limit)
         |> Enum.map(fn message ->
           %{
             "id" => message.id,
             "from" => message.sender_session,
             "to" => message.recipient,
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
      argument(:limit, :integer, allow_nil?: false)

      run(fn input, _context ->
        limit = Map.get(input.arguments, :limit) || 30

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
