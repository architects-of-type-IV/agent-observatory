defmodule Ichor.Gateway.EventBridge do
  @moduledoc """
  Bridges the events:stream into gateway:messages by transforming
  persisted event records into DecisionLog format.

  Subscribes to "events:stream" and broadcasts the transformed
  DecisionLog on "gateway:messages" so the dashboard's gateway
  handlers receive live data from all Claude Code sessions.
  """

  use GenServer

  alias Ichor.Gateway.{EntropyTracker, TopologyBuilder}
  alias Ichor.Mesh.CausalDAG
  alias Ichor.Mesh.DecisionLog
  alias Ichor.Mesh.DecisionLog.Helpers, as: DLHelpers
  alias Ichor.Signals.Message

  @doc "Start the EventBridge GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @sweep_interval :timer.hours(1)
  @stale_ttl_seconds 7_200

  @impl true
  def init(_opts) do
    Ichor.Signals.subscribe(:events)
    schedule_sweep()
    {:ok, %{last_event: %{}, last_seen: %{}}}
  end

  @impl true
  def handle_info(%Message{name: :new_event, data: %{event: event}}, state) do
    maybe_register_agent(event)
    log = event_to_decision_log(event)
    log = maybe_enrich_entropy(log)

    Ichor.Signals.emit(:decision_log, %{log: log})

    state = maybe_insert_dag_node(log, state)

    {:noreply, state}
  end

  def handle_info(:sweep, state) do
    cutoff = System.monotonic_time(:second) - @stale_ttl_seconds

    stale_sids =
      state.last_seen
      |> Enum.filter(fn {_sid, ts} -> ts < cutoff end)
      |> Enum.map(&elem(&1, 0))

    new_last_event = Map.drop(state.last_event, stale_sids)
    new_last_seen = Map.drop(state.last_seen, stale_sids)

    schedule_sweep()
    {:noreply, %{state | last_event: new_last_event, last_seen: new_last_seen}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval)
  end

  defp event_to_decision_log(event) do
    %DecisionLog{
      meta: %{
        trace_id: event.session_id,
        timestamp: event.inserted_at,
        source_app: event.source_app,
        tool_use_id: event.tool_use_id,
        event_id: event.id,
        parent_step_id: nil,
        cluster_id: extract_team_name(event)
      },
      identity: %{
        agent_id: event.session_id,
        agent_type: event.source_app || "unknown",
        capability_version: "1.0.0",
        model_name: event.model_name
      },
      cognition: %{
        intent: map_intent(event),
        hook_event_type: to_string(event.hook_event_type),
        summary: event.summary
      },
      action: build_action(event),
      state_delta: nil,
      control: build_control(event)
    }
  end

  defp map_intent(event) do
    intent(event.hook_event_type, event.tool_name, event.payload)
  end

  defp intent(:PreToolUse, "TeamCreate", payload) do
    team = get_in(payload, ["tool_input", "team_name"]) || "unknown"
    "team_create:#{team}"
  end

  defp intent(:PostToolUse, "TeamCreate", payload) do
    team = get_in(payload, ["tool_input", "team_name"]) || "unknown"
    "team_created:#{team}"
  end

  defp intent(:PreToolUse, "TeamDelete", _payload), do: "team_delete"
  defp intent(:PostToolUse, "TeamDelete", _payload), do: "team_deleted"

  defp intent(:PreToolUse, "SendMessage", payload) do
    recipient = get_in(payload, ["tool_input", "recipient"]) || "all"
    msg_type = get_in(payload, ["tool_input", "type"]) || "message"
    "send_#{msg_type}:#{recipient}"
  end

  defp intent(:PostToolUse, "SendMessage", payload) do
    recipient = get_in(payload, ["tool_input", "recipient"]) || "all"
    msg_type = get_in(payload, ["tool_input", "type"]) || "message"
    "sent_#{msg_type}:#{recipient}"
  end

  defp intent(:PreToolUse, "Task", payload) do
    agent_type = get_in(payload, ["tool_input", "subagent_type"]) || "general"
    "spawn_agent:#{agent_type}"
  end

  defp intent(:PostToolUse, "Task", payload) do
    agent_type = get_in(payload, ["tool_input", "subagent_type"]) || "general"
    "agent_spawned:#{agent_type}"
  end

  defp intent(:PreToolUse, "TaskCreate", _payload), do: "task_create"
  defp intent(:PostToolUse, "TaskCreate", _payload), do: "task_created"

  defp intent(:PreToolUse, "TaskUpdate", payload) do
    case get_in(payload, ["tool_input", "status"]) do
      nil -> "task_update"
      status -> "task_update:#{status}"
    end
  end

  defp intent(:PostToolUse, "TaskUpdate", payload) do
    case get_in(payload, ["tool_input", "status"]) do
      nil -> "task_updated"
      status -> "task_updated:#{status}"
    end
  end

  defp intent(:PreToolUse, "TaskList", _payload), do: "task_list"
  defp intent(:PreToolUse, "TaskGet", _payload), do: "task_get"
  defp intent(:PreToolUse, "EnterWorktree", _payload), do: "enter_worktree"
  defp intent(:PostToolUse, "EnterWorktree", _payload), do: "worktree_entered"
  defp intent(:PreToolUse, "EnterPlanMode", _payload), do: "enter_plan_mode"
  defp intent(:PreToolUse, "ExitPlanMode", _payload), do: "exit_plan_mode"
  defp intent(:PreToolUse, tool, _payload), do: "tool_call:#{tool || "unknown"}"
  defp intent(:PostToolUse, tool, _payload), do: "tool_result:#{tool || "unknown"}"
  defp intent(:PostToolUseFailure, tool, _payload), do: "tool_failure:#{tool || "unknown"}"
  defp intent(:UserPromptSubmit, _tool, _payload), do: "user_prompt"
  defp intent(:SessionStart, _tool, _payload), do: "session_start"
  defp intent(:SessionEnd, _tool, _payload), do: "session_end"
  defp intent(:SubagentStart, _tool, _payload), do: "subagent_start"
  defp intent(:SubagentStop, _tool, _payload), do: "subagent_stop"
  defp intent(:PermissionRequest, _tool, _payload), do: "permission_request"
  defp intent(:Notification, _tool, _payload), do: "notification"
  defp intent(:Stop, _tool, _payload), do: "session_stop"
  defp intent(:PreCompact, _tool, _payload), do: "pre_compact"
  defp intent(other, _tool, _payload), do: to_string(other)

  defp extract_team_name(event) do
    # Try multiple payload locations for team context
    get_in(event.payload, ["tool_input", "team_name"]) ||
      get_in(event.payload, ["team_name"]) ||
      nil
  end

  defp build_action(event) do
    status = map_action_status(event.hook_event_type)

    %{
      status: status,
      tool_call: event.tool_name,
      tool_input: truncate_tool_input(event.payload),
      tool_output_summary: event.summary,
      duration_ms: event.duration_ms,
      permission_mode: event.permission_mode,
      cwd: event.cwd,
      payload: event.payload
    }
  end

  defp map_action_status(:PostToolUse), do: :success
  defp map_action_status(:PostToolUseFailure), do: :failure
  defp map_action_status(:PreToolUse), do: :pending
  defp map_action_status(:PermissionRequest), do: :pending
  defp map_action_status(_), do: :success

  defp build_control(%{hook_event_type: type}) when type in [:Stop, :SessionEnd],
    do: %{is_terminal: true}

  defp build_control(_event), do: nil

  defp maybe_register_agent(%{session_id: sid}) when is_binary(sid),
    do: EntropyTracker.register_agent(sid, sid)

  defp maybe_register_agent(_), do: :ok

  defp maybe_enrich_entropy(%DecisionLog{} = log) do
    with %{trace_id: session_id} when is_binary(session_id) <- log.meta,
         %{intent: intent} when is_binary(intent) <- log.cognition,
         %{tool_call: tool_call, status: action_status} <- log.action do
      case EntropyTracker.record_and_score(session_id, {intent, tool_call, action_status}) do
        {:ok, score, _severity} -> DLHelpers.put_gateway_entropy_score(log, score)
        _ -> log
      end
    else
      _ -> log
    end
  rescue
    _ -> log
  catch
    :exit, _ -> log
  end

  defp maybe_insert_dag_node(%DecisionLog{} = log, state) do
    with %{event_id: event_id, trace_id: session_id}
         when is_binary(event_id) and is_binary(session_id) <- log.meta,
         %{agent_id: agent_id} when is_binary(agent_id) <- log.identity,
         %{intent: intent} when is_binary(intent) <- log.cognition do
      parent_id = Map.get(state.last_event, session_id)
      node = build_dag_node(log, event_id, agent_id, intent, parent_id)
      TopologyBuilder.subscribe_to_session(session_id)
      CausalDAG.insert(session_id, node)

      %{
        state
        | last_event: Map.put(state.last_event, session_id, event_id),
          last_seen: Map.put(state.last_seen, session_id, System.monotonic_time(:second))
      }
    else
      _ -> state
    end
  rescue
    _ -> state
  catch
    :exit, _ -> state
  end

  defp build_dag_node(log, event_id, agent_id, intent, parent_id) do
    %CausalDAG.Node{
      trace_id: event_id,
      parent_step_id: parent_id,
      agent_id: agent_id,
      intent: intent,
      confidence_score: get_nested(log.cognition, :confidence_score, 0.0),
      entropy_score: get_nested(log.cognition, :entropy_score, 0.0),
      action_status: get_nested(log.action, :status, :pending),
      timestamp: get_nested(log.meta, :timestamp, DateTime.utc_now())
    }
  end

  defp get_nested(nil, _key, default), do: default
  defp get_nested(map, key, default) when is_map(map), do: Map.get(map, key, default)

  defp truncate_tool_input(%{"tool_input" => input}) when is_binary(input) do
    String.slice(input, 0, 500)
  end

  defp truncate_tool_input(%{"tool_input" => input}) when is_map(input) do
    input |> Jason.encode!() |> String.slice(0, 500)
  rescue
    _ -> nil
  end

  defp truncate_tool_input(_), do: nil
end
