defmodule Ichor.Signals.MailboxAdapter do
  @moduledoc """
  Delivers messages via BEAM-native AgentProcess mailboxes.
  This is the default delivery channel for agents reachable via MCP check_inbox.
  """

  @behaviour Ichor.Infrastructure.Channel

  alias Ichor.Infrastructure.AgentProcess
  alias Ichor.Signals.ProtocolTracker

  @impl true
  def channel_key, do: :mailbox

  @impl true
  def deliver(session_id, payload) when is_binary(session_id) do
    content = payload[:content] || payload["content"] || ""
    from = payload[:from] || payload["from"] || "ichor"
    msg_type = payload[:type] || payload["type"] || :text

    message = %{
      id: generate_id(),
      from: from,
      to: session_id,
      content: content,
      type: msg_type,
      timestamp: DateTime.utc_now(),
      metadata: Map.drop(payload, [:content, :from, :type, "content", "from", "type"])
    }

    AgentProcess.send_message(session_id, message)
    ProtocolTracker.track_mailbox_delivery(message.id, session_id, from)
    :ok
  end

  @impl true
  def available?(session_id) when is_binary(session_id) do
    session_id != ""
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
