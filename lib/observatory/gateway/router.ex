defmodule Observatory.Gateway.Router do
  @moduledoc """
  Central message bus for the Observatory Gateway.
  Provides `broadcast/2` for outbound messages and `ingest/1` for inbound events.

  Pipeline: Validate -> Route -> Deliver -> Audit
  """

  require Logger

  alias Observatory.Gateway.{AgentRegistry, Envelope, SchemaInterceptor}
  alias Observatory.Gateway.Channels.{MailboxAdapter, Tmux, WebhookAdapter}

  @doc """
  Broadcast a message to a channel pattern.
  Channel patterns: "agent:{name}", "team:{name}", "role:{role}", "session:{id}", "fleet:all"

  Returns {:ok, delivery_count} or {:error, reason}.
  """
  def broadcast(channel, payload) when is_binary(channel) and is_map(payload) do
    envelope = Envelope.new(channel, payload, from: payload[:from] || payload["from"])

    with :ok <- validate(envelope),
         recipients when recipients != [] <- route(envelope),
         delivered <- deliver(envelope, recipients) do
      audit(envelope, recipients, delivered)
      track_protocol_trace(envelope, recipients, delivered)
      {:ok, delivered}
    else
      {:error, reason} ->
        Logger.warning("Gateway broadcast failed: #{inspect(reason)}")
        {:error, reason}

      [] ->
        Logger.debug("Gateway broadcast to #{channel}: no recipients found")
        audit(envelope, [], 0)
        {:ok, 0}
    end
  end

  @doc """
  Ingest an inbound hook event into the gateway pipeline.
  Updates the AgentRegistry and broadcasts to the activity stream.
  """
  def ingest(event) do
    # Update the unified agent registry
    AgentRegistry.register_from_event(event)

    # Mark ended sessions
    if event.hook_event_type in [:SessionEnd, "SessionEnd"] do
      AgentRegistry.mark_ended(event.session_id)
    end

    # Broadcast to the per-agent activity stream
    agent = AgentRegistry.get(event.session_id)
    agent_name = if agent, do: agent.id, else: event.session_id

    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "agent:#{agent_name}:activity",
      {:agent_event, event}
    )

    :ok
  end

  # ── Pipeline Stages ──────────────────────────────────────────────────

  defp validate(envelope) do
    case SchemaInterceptor.validate_envelope(envelope) do
      :ok -> :ok
      {:error, reason} -> {:error, {:validation_failed, reason}}
    end
  end

  defp route(envelope) do
    AgentRegistry.resolve_channel(envelope.channel)
  end

  defp deliver(envelope, recipients) do
    Enum.reduce(recipients, 0, fn agent, count ->
      delivered = deliver_to_agent(agent, envelope.payload)
      count + delivered
    end)
  end

  defp deliver_to_agent(agent, payload) do
    # Always write to mailbox so check_inbox works regardless of delivery channel
    mailbox_ok =
      if agent.channels[:mailbox] do
        MailboxAdapter.deliver(agent.channels.mailbox, payload) == :ok
      else
        false
      end

    # Tmux is additive -- push to terminal when available
    if agent.channels[:tmux] && Tmux.available?(agent.channels.tmux) do
      Tmux.deliver(agent.channels.tmux, payload)
    end

    # Webhook is additive -- fire alongside when configured
    if agent.channels[:webhook] do
      webhook_payload = Map.put(payload, :agent_id, agent.session_id)
      WebhookAdapter.deliver(agent.channels.webhook, webhook_payload)
    end

    if mailbox_ok, do: 1, else: 0
  end

  defp track_protocol_trace(envelope, recipients, delivered) do
    recipient_ids = Enum.map(recipients, & &1.id)
    content = envelope.payload[:content] || envelope.payload["content"] || ""

    Observatory.ProtocolTracker.track_gateway_broadcast(%{
      trace_id: envelope.trace_id,
      from: envelope.from,
      channel: envelope.channel,
      recipients: recipient_ids,
      delivered: delivered,
      content_preview: String.slice(content, 0, 100),
      timestamp: envelope.timestamp
    })
  end

  defp audit(envelope, recipients, delivered_count) do
    audit_entry = %{
      envelope_id: envelope.id,
      channel: envelope.channel,
      from: envelope.from,
      recipient_count: length(recipients),
      delivered_count: delivered_count,
      timestamp: envelope.timestamp,
      trace_id: envelope.trace_id
    }

    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "gateway:audit",
      {:gateway_audit, audit_entry}
    )
  end
end
