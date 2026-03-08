defmodule Observatory.Gateway.Channels.MailboxAdapter do
  @moduledoc """
  Delivers messages via the Observatory.Mailbox ETS store + CommandQueue filesystem.
  This is the default delivery channel for agents reachable via MCP check_inbox.
  """

  @behaviour Observatory.Gateway.Channel

  @impl true
  def channel_key, do: :mailbox

  @impl true
  def deliver(session_id, payload) when is_binary(session_id) do
    content = payload[:content] || payload["content"] || ""
    from = payload[:from] || payload["from"] || "observatory"
    msg_type = payload[:type] || payload["type"] || :text

    metadata =
      Map.drop(payload, [:content, :from, :type, "content", "from", "type"])
      |> Map.put(:via_gateway, true)

    case Observatory.Mailbox.send_message(session_id, from, content, type: msg_type, metadata: metadata) do
      {:ok, message} ->
        Observatory.ProtocolTracker.track_mailbox_delivery(message.id, session_id, from)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def available?(session_id) when is_binary(session_id) do
    # Mailbox is always available -- it's ETS-backed, no external dependency
    is_binary(session_id) and session_id != ""
  end
end
