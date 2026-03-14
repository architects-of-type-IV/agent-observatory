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
  alias Ichor.Gateway.AgentRegistry.AgentEntry
  alias Ichor.Gateway.{Envelope, SchemaInterceptor}
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
  Ensures an AgentProcess exists, handles channel side effects, and broadcasts.
  """
  def ingest(event) do
    agent_id = resolve_or_create_agent(event.session_id, event)

    if event.hook_event_type in [:SessionEnd, "SessionEnd"] do
      AgentProcess.update_fields(agent_id, %{status: :ended})
      terminate_agent_process(agent_id)
    end

    handle_channel_events(event)

    Ichor.Signals.emit(:agent_event, agent_id, %{event: event})

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

  # Signal only -- no delivery. The MCP tool path (Operator.send) handles
  # authoritative delivery. Emitting here gives dashboard visibility without
  # causing double-delivery from hook intercept + MCP tool.
  defp handle_send_message(event, input) do
    recipient = input["recipient"]
    content = input["content"] || input["summary"] || ""

    Ichor.Signals.emit(:agent_message_intercepted, event.session_id, %{
      from: event.session_id,
      to: recipient,
      content: String.slice(content, 0, 200),
      type: input["type"] || "message"
    })
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

  # Resolve event to the correct AgentProcess. If the UUID session_id already
  # has a process, use it. If not, check if an existing agent owns the same
  # tmux session (e.g. MES agent registered as "mes-XXX-coordinator" but
  # Claude fires events with UUID session_id and tmux_session "mes-XXX").
  # Returns the agent_id to use for signal emission.
  @spec resolve_or_create_agent(String.t(), map()) :: String.t()
  defp resolve_or_create_agent(session_id, event) do
    cond do
      AgentProcess.alive?(session_id) ->
        session_id

      match = find_agent_by_tmux(event.tmux_session) ->
        match

      true ->
        tmux_session = if event.tmux_session != "", do: event.tmux_session, else: nil

        opts = [
          id: session_id,
          role: :worker,
          backend: if(tmux_session, do: %{type: :tmux, session: tmux_session}, else: nil),
          metadata: %{
            cwd: event.cwd,
            model: event.model_name,
            os_pid: event.os_pid,
            name: session_id
          }
        ]

        case FleetSupervisor.spawn_agent(opts) do
          {:ok, _pid} -> session_id
          {:error, {:already_started, _}} -> session_id
          {:error, _reason} -> session_id
        end
    end
  rescue
    _ -> session_id
  end

  # Find an existing agent whose tmux session or target matches the event's tmux_session.
  # "mes-XXX" matches "mes-XXX:coordinator" (prefix match on tmux_target).
  defp find_agent_by_tmux(nil), do: nil
  defp find_agent_by_tmux(""), do: nil

  defp find_agent_by_tmux(tmux_session) do
    AgentProcess.list_all()
    |> Enum.find_value(fn {id, meta} ->
      target = meta[:tmux_target] || ""
      session = meta[:tmux_session] || ""

      if session == tmux_session or String.starts_with?(target, tmux_session <> ":") do
        id
      end
    end)
  end

  # ── Pipeline Stages ──────────────────────────────────────────────────

  defp validate(envelope) do
    case SchemaInterceptor.validate_envelope(envelope) do
      :ok -> :ok
      {:error, reason} -> {:error, {:validation_failed, reason}}
    end
  end

  defp route(envelope) do
    resolve_recipients(envelope.channel)
  end

  defp resolve_recipients("agent:" <> name) do
    AgentProcess.list_all()
    |> Enum.filter(fn {id, meta} ->
      id == name || meta[:short_name] == name || meta[:name] == name
    end)
    |> Enum.map(fn {id, meta} -> recipient_from_meta(id, meta) end)
  end

  defp resolve_recipients("session:" <> sid) do
    case AgentProcess.lookup(sid) do
      {_pid, meta} -> [recipient_from_meta(sid, meta)]
      nil -> []
    end
  end

  defp resolve_recipients("team:" <> team_name) do
    AgentProcess.list_all()
    |> Enum.filter(fn {_id, meta} -> meta[:team] == team_name end)
    |> Enum.map(fn {id, meta} -> recipient_from_meta(id, meta) end)
  end

  defp resolve_recipients("role:" <> role_str) do
    role = AgentEntry.role_from_string(role_str)

    AgentProcess.list_all()
    |> Enum.filter(fn {_id, meta} -> meta[:role] == role end)
    |> Enum.map(fn {id, meta} -> recipient_from_meta(id, meta) end)
  end

  defp resolve_recipients("fleet:" <> _) do
    AgentProcess.list_all()
    |> Enum.filter(fn {_id, meta} -> meta[:status] == :active end)
    |> Enum.map(fn {id, meta} -> recipient_from_meta(id, meta) end)
  end

  defp resolve_recipients(_unknown), do: []

  defp recipient_from_meta(id, meta) do
    %{
      id: id,
      session_id: meta[:session_id] || id,
      channels: meta[:channels] || %{}
    }
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

    Ichor.Signals.emit(:gateway_audit, %{
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
