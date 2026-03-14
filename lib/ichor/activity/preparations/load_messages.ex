defmodule Ichor.Activity.Preparations.LoadMessages do
  @moduledoc """
  Loads messages from SendMessage hook events in the EventBuffer.
  """

  use Ash.Resource.Preparation

  alias Ash.DataLayer.Simple
  alias Ichor.EventBuffer

  @impl true
  def prepare(query, _opts, _context) do
    hook_messages =
      EventBuffer.list_events()
      |> Enum.filter(&send_message_event?/1)
      |> Enum.map(&event_to_message/1)

    all = Enum.sort_by(hook_messages, & &1.timestamp, {:desc, DateTime})

    Simple.set_data(query, all)
  end

  # Match both Claude-native SendMessage and MCP send_message tool calls
  defp send_message_event?(%{hook_event_type: :PreToolUse, tool_name: "SendMessage"}), do: true

  defp send_message_event?(%{
         hook_event_type: :PreToolUse,
         tool_name: "mcp__ichor__send_message"
       }), do: true

  defp send_message_event?(_), do: false

  defp event_to_message(e) do
    input = (e.payload || %{})["tool_input"] || %{}

    # MCP tools nest args under "input" key
    args = input["input"] || input

    struct!(Ichor.Activity.Message, %{
      id: e.id,
      sender_session: e.session_id,
      sender_app: e.source_app,
      type: args["type"] || "message",
      recipient: args["recipient"] || args["to_session_id"],
      content: args["content"] || args["summary"] || "",
      summary: args["summary"],
      timestamp: e.inserted_at
    })
  end
end
