defmodule Ichor.Observability.Preparations.LoadMessages do
  @moduledoc """
  Loads messages from SendMessage hook events in the EventBuffer.
  """

  use Ash.Resource.Preparation

  alias Ash.DataLayer.Simple
  alias Ichor.Observability.Preparations.EventBufferReader

  @impl true
  def prepare(query, _opts, _context) do
    hook_messages =
      EventBufferReader.list_events()
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
       }),
       do: true

  defp send_message_event?(_), do: false

  defp event_to_message(e) do
    input = get_in(e, [:payload, "tool_input"]) || %{}
    args = parse_args(input)

    struct!(Ichor.Observability.Message, %{
      id: e.id,
      sender_session: pick(args, ["from_session_id", "from"], e.session_id),
      sender_app: e.source_app,
      type: Map.get(args, "type", "message"),
      recipient: pick(args, ["to_session_id", "recipient", "to"], nil),
      content: pick(args, ["content", "summary"], ""),
      summary: args["summary"],
      timestamp: e.inserted_at,
      transport: derive_transport(e.tool_name)
    })
  end

  defp derive_transport("mcp__ichor__send_message"), do: :mcp
  defp derive_transport(_), do: :hook

  defp pick(map, keys, default) do
    Enum.find_value(keys, default, &map[&1])
  end

  # MCP tools nest args under "input" key; sometimes as a JSON string
  defp parse_args(%{"input" => inner}) when is_map(inner), do: inner
  defp parse_args(%{"input" => json}) when is_binary(json), do: safe_decode(json)
  defp parse_args(map) when is_map(map), do: map
  defp parse_args(json) when is_binary(json), do: safe_decode(json)
  defp parse_args(_), do: %{}

  defp safe_decode(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> map
      _ -> %{"content" => json}
    end
  end
end
