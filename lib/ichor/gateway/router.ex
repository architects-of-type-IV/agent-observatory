defmodule Ichor.Gateway.Router do
  @moduledoc """
  Central message bus for the Gateway.
  Provides `broadcast/2` for outbound messages and `ingest/1` for inbound events.

  Pipeline: Validate -> Resolve -> Deliver -> Audit
  """

  require Logger

  alias Ichor.Control.AgentProcess
  alias Ichor.Gateway.AgentRegistry.AgentEntry
  alias Ichor.Gateway.{Envelope, SchemaInterceptor}
  alias Ichor.Gateway.Router.EventIngest
  alias Ichor.ProtocolTracker
  alias Ichor.Signals

  @default_channels [
    {Ichor.Gateway.Channels.MailboxAdapter, primary: true},
    {Ichor.Gateway.Channels.Tmux, primary: false},
    {Ichor.Gateway.Channels.WebhookAdapter, primary: false}
  ]

  @doc "Return the configured channel adapters as `[{module, opts}]`."
  @spec channels() :: [{module(), keyword()}]
  def channels do
    Application.get_env(:ichor, :channels, @default_channels)
  end

  @doc """
  Broadcast a message to a channel pattern.
  Channel patterns: "agent:{name}", "team:{name}", "role:{role}", "session:{id}", "fleet:all"

  Returns `{:ok, delivery_count}` or `{:error, reason}`.
  """
  @spec broadcast(String.t(), map()) :: {:ok, non_neg_integer()} | {:error, term()}
  def broadcast(channel, payload) when is_binary(channel) and is_map(payload) do
    envelope = Envelope.new(channel, payload, from: payload[:from] || payload["from"])

    with :ok <- validate(envelope),
         recipients when recipients != [] <- resolve(envelope.channel),
         delivered <- deliver(envelope, recipients, channels()) do
      record(envelope, recipients, delivered)
      {:ok, delivered}
    else
      {:error, reason} ->
        Logger.warning("Gateway broadcast failed: #{inspect(reason)}")
        {:error, reason}

      [] ->
        Logger.debug("Gateway broadcast to #{channel}: no recipients found")
        record(envelope, [], 0)
        {:ok, 0}
    end
  end

  @doc """
  Ingest an inbound hook event into the gateway pipeline.
  Ensures an AgentProcess exists, handles channel side effects, and emits signals.
  """
  @spec ingest(map()) :: :ok | {:error, term()}
  def ingest(event), do: EventIngest.ingest(event)

  # --- Validation ---

  defp validate(envelope) do
    case SchemaInterceptor.validate_envelope(envelope) do
      :ok -> :ok
      {:error, reason} -> {:error, {:validation_failed, reason}}
    end
  end

  # --- Recipient resolution ---

  defp resolve("agent:" <> name) do
    Enum.flat_map(AgentProcess.list_all(), fn {id, meta} ->
      if id == name || meta[:short_name] == name || meta[:name] == name do
        [recipient_from_meta(id, meta)]
      else
        []
      end
    end)
  end

  defp resolve("session:" <> sid) do
    case AgentProcess.lookup(sid) do
      {_pid, meta} -> [recipient_from_meta(sid, meta)]
      nil -> []
    end
  end

  defp resolve("team:" <> team_name) do
    Enum.flat_map(AgentProcess.list_all(), fn {id, meta} ->
      if meta[:team] == team_name, do: [recipient_from_meta(id, meta)], else: []
    end)
  end

  defp resolve("role:" <> role_str) do
    role = AgentEntry.role_from_string(role_str)

    Enum.flat_map(AgentProcess.list_all(), fn {id, meta} ->
      if meta[:role] == role, do: [recipient_from_meta(id, meta)], else: []
    end)
  end

  defp resolve("fleet:" <> _) do
    Enum.flat_map(AgentProcess.list_all(), fn {id, meta} ->
      if meta[:status] == :active, do: [recipient_from_meta(id, meta)], else: []
    end)
  end

  defp resolve(_unknown), do: []

  defp recipient_from_meta(id, meta) do
    %{
      id: id,
      session_id: meta[:session_id] || id,
      channels: meta[:channels] || %{}
    }
  end

  # --- Delivery ---

  defp deliver(envelope, recipients, channels) do
    Enum.reduce(recipients, 0, fn agent, count ->
      count + deliver_to_agent(agent, envelope.payload, channels)
    end)
  end

  defp deliver_to_agent(agent, payload, channels) do
    Enum.reduce(channels, 0, fn {mod, opts}, count ->
      key = mod.channel_key()
      address = (agent[:channels] || %{})[key]
      skip? = function_exported?(mod, :skip?, 1) and mod.skip?(payload)
      deliver_via_channel(mod, opts, key, address, agent, payload, skip?, count)
    end)
  end

  defp deliver_via_channel(_mod, _opts, _key, nil, _agent, _payload, _skip?, count), do: count
  defp deliver_via_channel(_mod, _opts, _key, _address, _agent, _payload, true, count), do: count

  defp deliver_via_channel(mod, opts, key, address, agent, payload, false, count) do
    if mod.available?(address) do
      deliver_payload =
        if key == :webhook,
          do: Map.put(payload, :agent_id, agent[:session_id] || agent[:id]),
          else: payload

      count_after_deliver(mod, opts, address, deliver_payload, count)
    else
      count
    end
  end

  defp count_after_deliver(mod, opts, address, deliver_payload, count) do
    case mod.deliver(address, deliver_payload) do
      :ok -> if Keyword.get(opts, :primary, false), do: count + 1, else: count
      {:error, _} -> count
    end
  end

  # --- Audit ---

  defp record(envelope, recipients, delivered_count) do
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
