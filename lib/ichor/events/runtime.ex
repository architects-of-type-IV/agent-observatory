defmodule Ichor.Events.Runtime do
  @moduledoc """
  Unified event runtime. Canonical entry point for all inbound events.

  Public API:
  - `ingest_raw/1`           -- normalize a raw hook map, store, and emit signals
  - `record_heartbeat/2`     -- normalize a heartbeat into an Event, update liveness
  - `publish_fact/2`         -- publish an internal fact (watchdog probes, etc.)
  - `subscribe/2`            -- subscribe to the normalized event stream
  - `latest_session_state/1` -- liveness/alias/last-seen for a session
  """

  require Logger

  alias Ichor.Control.{AgentProcess, FleetSupervisor, TeamSupervisor}
  alias Ichor.EventBuffer
  alias Ichor.Events.Event
  alias Ichor.Gateway.HeartbeatManager
  alias Ichor.Signals

  @doc "Ingest a raw hook event map. Normalizes, stores, emits signals, and runs side effects."
  @spec ingest_raw(map()) :: {:ok, map()}
  def ingest_raw(raw_map) when is_map(raw_map) do
    {:ok, event} = EventBuffer.ingest(raw_map)
    Signals.emit(:new_event, %{event: event})
    ingest_event(event)
    {:ok, event}
  end

  @doc "Record a heartbeat for an agent session. Delegates to HeartbeatManager."
  @spec record_heartbeat(String.t(), String.t()) :: :ok
  def record_heartbeat(agent_id, cluster_id)
      when is_binary(agent_id) and is_binary(cluster_id) do
    HeartbeatManager.record_heartbeat(agent_id, cluster_id)
  end

  @doc "Publish an internal fact (watchdog probes, system events, etc.)."
  @spec publish_fact(atom(), map()) :: :ok
  def publish_fact(name, attrs \\ %{}) when is_atom(name) and is_map(attrs) do
    _event = build_fact_event(name, attrs)
    Signals.emit(:new_event, %{name: name, attrs: attrs})
    :ok
  end

  @doc "Subscribe to the normalized event stream. Delegates to Signals."
  @spec subscribe(atom(), keyword()) :: :ok | {:error, term()}
  def subscribe(topic, opts \\ []) when is_atom(topic) do
    case Keyword.get(opts, :scope_id) do
      nil -> Signals.subscribe(topic)
      scope_id -> Signals.subscribe(topic, scope_id)
    end
  end

  @doc "Returns liveness metadata for a session from the heartbeat store."
  @spec latest_session_state(String.t()) :: map() | nil
  def latest_session_state(session_id) when is_binary(session_id) do
    HeartbeatManager.get_session_state(session_id)
  end

  # Ingest pipeline -- absorbs former Gateway.Router.ingest/1

  defp ingest_event(event) do
    agent_id = resolve_or_create_agent(event.session_id, event)

    if event.hook_event_type in [:SessionEnd, "SessionEnd"] do
      AgentProcess.update_fields(agent_id, %{status: :ended})
      terminate_agent_process(agent_id)
    end

    handle_channel_events(event)
    Signals.emit(:agent_event, agent_id, %{event: event})
    :ok
  end

  defp handle_channel_events(%{hook_event_type: :SessionStart}), do: :ok

  defp handle_channel_events(%{hook_event_type: :PreToolUse} = event) do
    input = (event.payload || %{})["tool_input"] || %{}
    handle_pre_tool_use(event.tool_name, event, input)
  end

  defp handle_channel_events(_event), do: :ok

  defp handle_pre_tool_use("TeamCreate", _event, input), do: handle_team_create(input)
  defp handle_pre_tool_use("TeamDelete", _event, input), do: handle_team_delete(input)

  defp handle_pre_tool_use("SendMessage", event, input) do
    emit_intercepted(
      event,
      input["recipient"],
      input["content"] || input["summary"] || "",
      input["type"]
    )
  end

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

  defp emit_intercepted(event, recipient, content, type) do
    Signals.emit(:agent_message_intercepted, event.session_id, %{
      from: event.session_id,
      to: recipient,
      content: String.slice(content, 0, 200),
      type: type || "message"
    })
  end

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
            "[Events.Runtime] Could not create TeamSupervisor for #{team_name}: #{inspect(reason)}"
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

  # Private helpers

  defp build_fact_event(name, attrs) do
    %Event{
      id: Ash.UUID.generate(),
      kind: :fact,
      name: name,
      session_id: attrs[:session_id],
      payload: attrs,
      timestamp: DateTime.utc_now()
    }
  end
end
