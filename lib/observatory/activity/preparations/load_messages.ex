defmodule Observatory.Activity.Preparations.LoadMessages do
  @moduledoc """
  Loads messages from SendMessage hook events in the EventBuffer.
  """

  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context) do
    hook_messages =
      Observatory.EventBuffer.list_events()
      |> Enum.filter(fn e ->
        e.hook_event_type == :PreToolUse and e.tool_name == "SendMessage"
      end)
      |> Enum.map(fn e ->
        input = (e.payload || %{})["tool_input"] || %{}

        struct!(Observatory.Activity.Message, %{
          id: e.id,
          sender_session: e.session_id,
          sender_app: e.source_app,
          type: input["type"] || "message",
          recipient: input["recipient"],
          content: input["content"] || input["summary"] || "",
          summary: input["summary"],
          timestamp: e.inserted_at
        })
      end)

    hook_ids = MapSet.new(hook_messages, & &1.id)

    mailbox_messages =
      Observatory.Mailbox.all_messages(200)
      |> Enum.reject(fn m -> MapSet.member?(hook_ids, m.id) end)
      |> Enum.map(fn m ->
        struct!(Observatory.Activity.Message, %{
          id: m.id,
          sender_session: m.from,
          sender_app: nil,
          type: to_string(m.type || "message"),
          recipient: m.to,
          content: m.content || "",
          summary: nil,
          timestamp: m.timestamp
        })
      end)

    all = (hook_messages ++ mailbox_messages)
          |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})

    Ash.DataLayer.Simple.set_data(query, all)
  end
end
