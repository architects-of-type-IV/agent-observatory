defmodule Ichor.Activity.Preparations.LoadMessages do
  @moduledoc """
  Loads messages from SendMessage hook events in the EventBuffer.
  """

  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context) do
    hook_messages =
      Ichor.EventBuffer.list_events()
      |> Enum.filter(fn e ->
        e.hook_event_type == :PreToolUse and e.tool_name == "SendMessage"
      end)
      |> Enum.map(fn e ->
        input = (e.payload || %{})["tool_input"] || %{}

        struct!(Ichor.Activity.Message, %{
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

    all = Enum.sort_by(hook_messages, & &1.timestamp, {:desc, DateTime})

    Ash.DataLayer.Simple.set_data(query, all)
  end
end
