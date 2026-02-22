defmodule Observatory.Gateway.EventBridge do
  @moduledoc """
  Bridges the events:stream into gateway:messages by transforming
  Observatory.Events.Event structs into DecisionLog format.

  Subscribes to "events:stream" and broadcasts the transformed
  DecisionLog on "gateway:messages" so the dashboard's gateway
  handlers receive live data from all Claude Code sessions.
  """

  use GenServer

  alias Observatory.Gateway.EntropyTracker
  alias Observatory.Mesh.CausalDAG
  alias Observatory.Mesh.DecisionLog

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Observatory.PubSub, "events:stream")
    {:ok, %{last_event: %{}}}
  end

  @impl true
  def handle_info({:new_event, event}, state) do
    maybe_register_agent(event)
    log = event_to_decision_log(event)
    log = maybe_enrich_entropy(log)

    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "gateway:messages",
      {:decision_log, log}
    )

    state = maybe_insert_dag_node(log, state)

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Transform ────────────────────────────────────────────────────

  defp event_to_decision_log(event) do
    %DecisionLog{
      meta: %DecisionLog.Meta{
        trace_id: event.session_id,
        timestamp: event.inserted_at,
        source_app: event.source_app,
        tool_use_id: event.tool_use_id,
        event_id: event.id,
        parent_step_id: nil,
        cluster_id: extract_team_name(event)
      },
      identity: %DecisionLog.Identity{
        agent_id: event.session_id,
        agent_type: event.source_app || "unknown",
        capability_version: "1.0.0",
        model_name: event.model_name
      },
      cognition: %DecisionLog.Cognition{
        intent: map_intent(event),
        hook_event_type: to_string(event.hook_event_type),
        summary: event.summary
      },
      action: build_action(event),
      state_delta: nil,
      control: build_control(event)
    }
  end

  # Team-aware intent mapping: extracts semantic meaning from tool payloads
  defp map_intent(event) do
    case {event.hook_event_type, event.tool_name} do
      # Team lifecycle
      {:PreToolUse, "TeamCreate"} ->
        team = get_in(event.payload, ["tool_input", "team_name"]) || "unknown"
        "team_create:#{team}"

      {:PostToolUse, "TeamCreate"} ->
        team = get_in(event.payload, ["tool_input", "team_name"]) || "unknown"
        "team_created:#{team}"

      {:PreToolUse, "TeamDelete"} ->
        "team_delete"

      {:PostToolUse, "TeamDelete"} ->
        "team_deleted"

      # Messaging
      {:PreToolUse, "SendMessage"} ->
        recipient = get_in(event.payload, ["tool_input", "recipient"]) || "all"
        msg_type = get_in(event.payload, ["tool_input", "type"]) || "message"
        "send_#{msg_type}:#{recipient}"

      {:PostToolUse, "SendMessage"} ->
        recipient = get_in(event.payload, ["tool_input", "recipient"]) || "all"
        msg_type = get_in(event.payload, ["tool_input", "type"]) || "message"
        "sent_#{msg_type}:#{recipient}"

      # Agent spawning
      {:PreToolUse, "Task"} ->
        agent_type = get_in(event.payload, ["tool_input", "subagent_type"]) || "general"
        "spawn_agent:#{agent_type}"

      {:PostToolUse, "Task"} ->
        agent_type = get_in(event.payload, ["tool_input", "subagent_type"]) || "general"
        "agent_spawned:#{agent_type}"

      # Task management
      {:PreToolUse, "TaskCreate"} ->
        "task_create"

      {:PostToolUse, "TaskCreate"} ->
        "task_created"

      {:PreToolUse, "TaskUpdate"} ->
        status = get_in(event.payload, ["tool_input", "status"])
        if status, do: "task_update:#{status}", else: "task_update"

      {:PostToolUse, "TaskUpdate"} ->
        status = get_in(event.payload, ["tool_input", "status"])
        if status, do: "task_updated:#{status}", else: "task_updated"

      {:PreToolUse, "TaskList"} ->
        "task_list"

      {:PreToolUse, "TaskGet"} ->
        "task_get"

      # Worktree
      {:PreToolUse, "EnterWorktree"} ->
        "enter_worktree"

      {:PostToolUse, "EnterWorktree"} ->
        "worktree_entered"

      # Plan mode
      {:PreToolUse, "EnterPlanMode"} ->
        "enter_plan_mode"

      {:PreToolUse, "ExitPlanMode"} ->
        "exit_plan_mode"

      # Generic tool calls
      {:PreToolUse, _} ->
        "tool_call:#{event.tool_name || "unknown"}"

      {:PostToolUse, _} ->
        "tool_result:#{event.tool_name || "unknown"}"

      {:PostToolUseFailure, _} ->
        "tool_failure:#{event.tool_name || "unknown"}"

      # Session lifecycle
      {:UserPromptSubmit, _} -> "user_prompt"
      {:SessionStart, _} -> "session_start"
      {:SessionEnd, _} -> "session_end"
      {:SubagentStart, _} -> "subagent_start"
      {:SubagentStop, _} -> "subagent_stop"
      {:PermissionRequest, _} -> "permission_request"
      {:Notification, _} -> "notification"
      {:Stop, _} -> "session_stop"
      {:PreCompact, _} -> "pre_compact"
      {other, _} -> to_string(other)
    end
  end

  defp extract_team_name(event) do
    # Try multiple payload locations for team context
    get_in(event.payload, ["tool_input", "team_name"]) ||
      get_in(event.payload, ["team_name"]) ||
      nil
  end

  defp build_action(event) do
    status = map_action_status(event.hook_event_type)

    %DecisionLog.Action{
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

  defp map_action_status(hook_event_type) do
    case hook_event_type do
      :PostToolUse -> :success
      :PostToolUseFailure -> :failure
      :PreToolUse -> :pending
      :PermissionRequest -> :pending
      _ -> :success
    end
  end

  defp build_control(event) do
    case event.hook_event_type do
      :Stop ->
        %DecisionLog.Control{is_terminal: true}

      :SessionEnd ->
        %DecisionLog.Control{is_terminal: true}

      _ ->
        nil
    end
  end

  defp maybe_register_agent(%{session_id: sid}) when is_binary(sid) do
    EntropyTracker.register_agent(sid, sid)
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp maybe_register_agent(_), do: :ok

  defp maybe_enrich_entropy(%DecisionLog{} = log) do
    with %{trace_id: session_id} when is_binary(session_id) <- log.meta,
         %{intent: intent} when is_binary(intent) <- log.cognition,
         %{tool_call: tool_call, status: action_status} <- log.action do
      case EntropyTracker.record_and_score(session_id, {intent, tool_call, action_status}) do
        {:ok, score, _severity} -> DecisionLog.put_gateway_entropy_score(log, score)
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

  defp maybe_enrich_entropy(log), do: log

  defp maybe_insert_dag_node(%DecisionLog{} = log, state) do
    with %{event_id: event_id, trace_id: session_id} when is_binary(event_id) and is_binary(session_id) <- log.meta,
         %{agent_id: agent_id} when is_binary(agent_id) <- log.identity,
         %{intent: intent} when is_binary(intent) <- log.cognition do
      parent_id = Map.get(state.last_event, session_id)

      node = %CausalDAG.Node{
        trace_id: event_id,
        parent_step_id: parent_id,
        agent_id: agent_id,
        intent: intent,
        confidence_score: (log.cognition && log.cognition.confidence_score) || 0.0,
        entropy_score: (log.cognition && log.cognition.entropy_score) || 0.0,
        action_status: (log.action && log.action.status) || :pending,
        timestamp: (log.meta && log.meta.timestamp) || DateTime.utc_now()
      }

      CausalDAG.insert(session_id, node)

      %{state | last_event: Map.put(state.last_event, session_id, event_id)}
    else
      _ -> state
    end
  rescue
    _ -> state
  catch
    :exit, _ -> state
  end

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
