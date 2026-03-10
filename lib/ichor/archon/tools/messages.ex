defmodule Ichor.Archon.Tools.Messages do
  @moduledoc """
  Messaging tools for Archon. Reads from Activity.Message, sends via Operator.
  """
  use Ash.Resource, domain: Ichor.Archon.Tools

  alias Ichor.Activity.Message, as: ActivityMessage
  alias Ichor.Operator

  actions do
    action :recent_messages, {:array, :map} do
      description(
        "Get recent inter-agent messages (operator/agent communications). NOT for conversation history -- your memory context has that."
      )

      argument :limit, :integer do
        allow_nil?(false)
        default(20)
        description("Max messages to return (default 20)")
      end

      run(fn input, _context ->
        limit = input.arguments[:limit] || 20

        messages =
          ActivityMessage.recent!()
          |> Enum.take(limit)
          |> Enum.map(fn m ->
            %{
              "id" => m.id,
              "from" => m.sender_session,
              "to" => m.recipient,
              "content" => String.slice(m.content || "", 0, 500),
              "type" => m.type,
              "timestamp" => m.timestamp
            }
          end)

        {:ok, messages}
      end)
    end

    action :send_message, :map do
      description("Send a message to an agent or team as the operator (Architect).")

      argument :to, :string do
        allow_nil?(false)
        description("Recipient: session ID, agent name, or team target (e.g. 'team:alpha')")
      end

      argument :content, :string do
        allow_nil?(false)
        description("Message content")
      end

      run(fn input, _context ->
        to = input.arguments.to
        content = input.arguments.content

        case Operator.send(to, content) do
          {:ok, delivered} ->
            {:ok, %{"status" => "sent", "to" => to, "delivered" => delivered}}

          {:error, reason} ->
            {:ok, %{"status" => "failed", "to" => to, "error" => inspect(reason)}}
        end
      end)
    end
  end
end
