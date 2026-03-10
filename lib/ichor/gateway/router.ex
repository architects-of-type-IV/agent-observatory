defmodule Ichor.Gateway.Router do
  @moduledoc """
  Central message bus for the Gateway.
  Provides `broadcast/2` for outbound messages and `ingest/1` for inbound events.

  Pipeline: Validate -> Route -> Deliver -> Audit

  Channels are registered at runtime via config:

      config :ichor, :channels, [
        {Ichor.Gateway.Channels.MailboxAdapter, primary: true},
        {Ichor.Gateway.Channels.Tmux, primary: false},
        {Ichor.Gateway.Channels.WebhookAdapter, primary: false}
      ]

  Any module implementing the `Ichor.Gateway.Channel` behaviour can be added.
  The first channel marked `primary: true` determines the delivery count.
  """

  require Logger

  alias Ichor.Fleet.{AgentProcess, FleetSupervisor, TeamSupervisor}
  alias Ichor.Gateway.{AgentRegistry, Envelope, SchemaInterceptor}
  alias Ichor.ProtocolTracker

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
  Updates the AgentRegistry, handles channel side effects, and broadcasts.
  """
  def ingest(event) do
    AgentRegistry.register_from_event(event)

    if event.hook_event_type in [:SessionEnd, "SessionEnd"] do
      AgentRegistry.mark_ended(event.session_id)
      terminate_agent_process(event.session_id)
    end

    handle_channel_events(event)

    agent = AgentRegistry.get(event.session_id)
    agent_name = if agent, do: agent.id, else: event.session_id

    Ichor.Signal.emit(:agent_event, agent_name, %{event: event})

    :ok
  end

  # ── Channel Side Effects ──────────────────────────────────────────

  defp handle_channel_events(%{hook_event_type: :SessionStart} = event) do
    Ichor.Channels.create_agent_channel(event.session_id)
  end

  defp handle_channel_events(%{hook_event_type: :PreToolUse} = event) do
    handle_pre_tool_use(event)
  end

  defp handle_channel_events(_event), do: :ok

  defp handle_pre_tool_use(event) do
    input = (event.payload || %{})["tool_input"] || %{}

    case event.tool_name do
      "TeamCreate" -> handle_team_create(input)
      "TeamDelete" -> handle_team_delete(input)
      "SendMessage" -> handle_send_message(event, input)
      _ -> :ok
    end
  end

  defp handle_team_create(input) do
    if team_name = input["team_name"] do
      Ichor.Channels.create_team_channel(team_name, [])
      ensure_team_supervisor(team_name)
    end
  end

  defp handle_team_delete(input) do
    if team_name = input["team_name"] do
      FleetSupervisor.disband_team(team_name)
    end
  end

  defp handle_send_message(event, input) do
    type = input["type"] || "message"
    recipient = input["recipient"]
    content = input["content"] || input["summary"] || ""

    payload = %{
      content: content,
      from: event.session_id,
      type: :text,
      metadata: %{
        source_app: event.source_app,
        summary: input["summary"],
        via: :hook_intercept
      }
    }

    case type do
      "message" when is_binary(recipient) ->
        broadcast("agent:#{recipient}", payload)

      "broadcast" ->
        if team_name = input["team_name"] do
          broadcast("team:#{team_name}", payload)
        end

      "shutdown_request" when is_binary(recipient) ->
        broadcast("agent:#{recipient}", payload)

      _ ->
        :ok
    end
  end

  @spec ensure_team_supervisor(String.t()) :: :ok
  defp ensure_team_supervisor(team_name) do
    unless TeamSupervisor.exists?(team_name) do
      case FleetSupervisor.create_team(name: team_name) do
        {:ok, _pid} ->
          :ok

        {:error, :already_exists} ->
          :ok

        {:error, reason} ->
          Logger.debug(
            "[Router] Could not create TeamSupervisor for #{team_name}: #{inspect(reason)}"
          )

          :ok
      end
    end
  rescue
    _ -> :ok
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
    Enum.reduce(channels(), 0, fn {mod, opts}, count ->
      key = mod.channel_key()
      address = agent.channels[key]

      skip? = function_exported?(mod, :skip?, 1) and mod.skip?(payload)

      if address && !skip? && mod.available?(address) do
        # Webhook gets agent_id injected for routing
        deliver_payload =
          if key == :webhook, do: Map.put(payload, :agent_id, agent.session_id), else: payload

        case mod.deliver(address, deliver_payload) do
          :ok -> if Keyword.get(opts, :primary, false), do: count + 1, else: count
          {:error, _} -> count
        end
      else
        count
      end
    end)
  end

  defp track_protocol_trace(envelope, recipients, delivered) do
    recipient_ids = Enum.map(recipients, & &1.id)
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

    Ichor.Signal.emit(:gateway_audit, %{
      envelope_id: audit_entry[:envelope_id],
      channel: audit_entry[:channel]
    })
  end

  # Stop the BEAM AgentProcess when a session ends, closing the lifecycle loop.
  # AgentProcess.terminate/2 handles cross-registry cleanup (AgentRegistry + EventBuffer).
  defp terminate_agent_process(session_id) do
    case AgentProcess.lookup(session_id) do
      {pid, _meta} ->
        FleetSupervisor.terminate_agent(session_id)
        |> case do
          :ok ->
            :ok

          {:error, :not_found} ->
            try do
              GenServer.stop(pid, :normal)
            catch
              :exit, _ -> :ok
            end
        end

      nil ->
        :ok
    end
  end
end
