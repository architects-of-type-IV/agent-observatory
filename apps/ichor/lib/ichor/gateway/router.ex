defmodule Ichor.Gateway.Router do
  @moduledoc """
  Central message bus for the Gateway.
  Provides `broadcast/2` for outbound messages and `ingest/1` for inbound events.

  Pipeline: Validate -> Resolve -> Deliver -> Audit
  """

  require Logger

  alias Ichor.Gateway.Router.{Audit, Delivery, EventIngest, RecipientResolver}
  alias Ichor.Gateway.{Envelope, SchemaInterceptor}

  @default_channels [
    {Ichor.Gateway.Channels.MailboxAdapter, primary: true},
    {Ichor.Gateway.Channels.Tmux, primary: false},
    {Ichor.Gateway.Channels.WebhookAdapter, primary: false}
  ]

  @doc "Return the configured channel adapters as `[{module, opts}]`."
  def channels do
    Application.get_env(:ichor, :channels, @default_channels)
  end

  @doc """
  Broadcast a message to a channel pattern.
  Channel patterns: "agent:{name}", "team:{name}", "role:{role}", "session:{id}", "fleet:all"

  Returns `{:ok, delivery_count}` or `{:error, reason}`.
  """
  def broadcast(channel, payload) when is_binary(channel) and is_map(payload) do
    envelope = Envelope.new(channel, payload, from: payload[:from] || payload["from"])

    with :ok <- validate(envelope),
         recipients when recipients != [] <- RecipientResolver.resolve(envelope.channel),
         delivered <- Delivery.deliver(envelope, recipients, channels()) do
      Audit.record(envelope, recipients, delivered)
      {:ok, delivered}
    else
      {:error, reason} ->
        Logger.warning("Gateway broadcast failed: #{inspect(reason)}")
        {:error, reason}

      [] ->
        Logger.debug("Gateway broadcast to #{channel}: no recipients found")
        Audit.record(envelope, [], 0)
        {:ok, 0}
    end
  end

  @doc """
  Ingest an inbound hook event into the gateway pipeline.
  Ensures an AgentProcess exists, handles channel side effects, and emits signals.
  """
  def ingest(event), do: EventIngest.ingest(event)

  defp validate(envelope) do
    case SchemaInterceptor.validate_envelope(envelope) do
      :ok -> :ok
      {:error, reason} -> {:error, {:validation_failed, reason}}
    end
  end
end
