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
    delivered = deliver_primary(agent, payload)

    # Webhook is additive -- fire alongside primary when configured
    if agent.channels[:webhook] do
      webhook_payload = Map.put(payload, :agent_id, agent.session_id)
      WebhookAdapter.deliver(agent.channels.webhook, webhook_payload)
    end

    delivered
  end

  defp deliver_primary(agent, payload) do
    # Priority: tmux > mailbox
    cond do
      agent.channels[:tmux] && Tmux.available?(agent.channels.tmux) ->
        case Tmux.deliver(agent.channels.tmux, payload) do
          :ok -> 1
          {:error, _} -> deliver_fallback_mailbox(agent, payload)
        end

      agent.channels[:mailbox] ->
        case MailboxAdapter.deliver(agent.channels.mailbox, payload) do
          :ok -> 1
          {:error, _} -> 0
        end

      true ->
        Logger.debug("No delivery channel for agent #{agent.id}")
        0
    end
  end

  defp deliver_fallback_mailbox(agent, payload) do
    if agent.channels[:mailbox] do
      case MailboxAdapter.deliver(agent.channels.mailbox, payload) do
        :ok -> 1
        {:error, _} -> 0
      end
    else
      0
    end
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
