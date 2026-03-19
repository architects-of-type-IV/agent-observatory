defmodule Ichor.Gateway.Router.EventIngest do
  @moduledoc """
  Inbound hook-event handling for the gateway pipeline.
  """

  require Logger

  alias Ichor.Control.{AgentProcess, FleetSupervisor, TeamSupervisor}

  @doc "Ingest a hook event: ensure agent process exists, handle channel side effects, emit signals."
  @spec ingest(map()) :: :ok
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
  # Delivery happens exclusively via the MCP path (/mcp -> AshAi -> MessageRouter).
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
    Ichor.Signals.emit(:agent_message_intercepted, event.session_id, %{
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
    Ichor.Signals.emit(:agent_message_intercepted, event.session_id, %{
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
