defmodule Ichor.Gateway.Router.Audit do
  @moduledoc """
  Gateway audit and protocol-trace side effects.
  """

  alias Ichor.ProtocolTracker
  alias Ichor.Signals

  @spec record(map(), [map()], non_neg_integer()) :: :ok
  def record(envelope, recipients, delivered_count) do
    emit_gateway_audit(envelope)
    track_protocol_trace(envelope, recipients, delivered_count)
    :ok
  end

  defp emit_gateway_audit(envelope) do
    Signals.emit(:gateway_audit, %{
      envelope_id: envelope.id,
      channel: envelope.channel
    })
  end

  defp track_protocol_trace(envelope, recipients, delivered) do
    recipient_ids = Enum.map(recipients, & &1[:id])
    content = envelope.payload[:content] || envelope.payload["content"] || ""

    ProtocolTracker.track_gateway_broadcast(%{
      trace_id: envelope.trace_id,
      from: envelope.from,
      channel: envelope.channel,
      recipients: recipient_ids,
      delivered: delivered,
      content_preview: String.slice(content, 0, 100),
      timestamp: envelope.timestamp
    })
  end
end
