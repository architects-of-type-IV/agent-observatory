defmodule Ichor.Gateway.Router do
  @moduledoc """
  Central message bus for the Gateway.
  Provides `broadcast/2` for outbound messages and `ingest/1` for inbound events.

  Pipeline: Validate -> Resolve -> Deliver -> Audit
  """

  require Logger

  alias Ichor.Control.{AgentProcess, FleetSupervisor, TeamSupervisor}
  alias Ichor.Gateway.AgentRegistry.AgentEntry
  alias Ichor.Gateway.{Envelope, SchemaInterceptor}
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
  def ingest(event) do
    agent_id = resolve_or_create_agent(event.session_id, event)

    if event.hook_event_type in [:SessionEnd, "SessionEnd"] do
      AgentProcess.update_fields(agent_id, %{status: :ended})
      terminate_agent_process(agent_id)
    end

    handle_channel_events(event)
    Signals.emit(:agent_event, agent_id, %{event: event})
    :ok
  end

  # Broadcast pipeline

  defp validate(envelope) do
    case SchemaInterceptor.validate_envelope(envelope) do
      :ok -> :ok
      {:error, reason} -> {:error, {:validation_failed, reason}}
    end
  end

  # NOTE: Ichor.Messages.Bus.resolve/1 matches the same prefix strings.
  # The two are intentionally separate: this function returns recipient maps
  # (used for channel delivery), while Bus.resolve/1 returns tagged tuples
  # (used for agent/team dispatch). A shared module would add indirection
  # without eliminating the shape difference.

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

  # Ingest pipeline

  defp handle_channel_events(%{hook_event_type: :SessionStart} = _event), do: :ok

  defp handle_channel_events(%{hook_event_type: :PreToolUse} = event) do
    input = (event.payload || %{})["tool_input"] || %{}
    handle_pre_tool_use(event.tool_name, event, input)
  end

  defp handle_channel_events(_event), do: :ok

  defp handle_pre_tool_use("TeamCreate", _event, input), do: handle_team_create(input)
  defp handle_pre_tool_use("TeamDelete", _event, input), do: handle_team_delete(input)

  # Claude-native SendMessage tool: observability signal only, no delivery.
  defp handle_pre_tool_use("SendMessage", event, input) do
    emit_intercepted(
      event,
      input["recipient"],
      input["content"] || input["summary"] || "",
      input["type"]
    )
  end

  # MCP send_message tool: PreToolUse is a monitoring event only.
  # Delivery happens exclusively via the MCP path (/mcp -> AshAi -> Messages.Bus).
  # Args are nested under "input" key in MCP tool_input.
  defp handle_pre_tool_use("mcp__ichor__send_message", event, input) do
    emit_intercepted_mcp(event, input["input"] || %{})
  end

  defp handle_pre_tool_use(_tool_name, _event, _input), do: :ok

  defp handle_team_create(input) do
    if team_name = input["team_name"] do
      ensure_team_supervisor(team_name)
    end
  end

  defp handle_team_delete(input) do
    if team_name = input["team_name"] do
      FleetSupervisor.disband_team(team_name)
    end
  end

  # Observability signal for Claude-native SendMessage tool.
  # Emits a signal so the dashboard can show the intercepted message.
  # Never delivers to agent mailboxes -- that is the tool's own responsibility.
  defp emit_intercepted(event, recipient, content, type) do
    Signals.emit(:agent_message_intercepted, event.session_id, %{
      from: event.session_id,
      to: recipient,
      content: String.slice(content, 0, 200),
      type: type || "message"
    })
  end

  # Observability signal for MCP mcp__ichor__send_message tool.
  # MCP tools nest arguments under an "input" key in tool_input.
  # The actual delivery happens via the MCP execution path -- NOT here.
  defp emit_intercepted_mcp(event, args) when is_map(args) do
    Signals.emit(:agent_message_intercepted, event.session_id, %{
      from: args["from_session_id"] || event.session_id,
      to: args["to_session_id"],
      content: String.slice(args["content"] || "", 0, 200),
      type: "message"
    })
  end

  defp emit_intercepted_mcp(_event, _args), do: :ok

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

  defp terminate_agent_process(session_id) do
    case AgentProcess.lookup(session_id) do
      {pid, _meta} -> terminate_or_stop(session_id, pid)
      nil -> :ok
    end
  end

  defp terminate_or_stop(session_id, pid) do
    case FleetSupervisor.terminate_agent(session_id) do
      :ok ->
        :ok

      {:error, :not_found} ->
        try do
          GenServer.stop(pid, :normal)
        catch
          :exit, _ -> :ok
        end
    end
  end
end
