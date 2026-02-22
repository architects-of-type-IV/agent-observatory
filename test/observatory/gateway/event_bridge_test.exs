defmodule Observatory.Gateway.EventBridgeTest do
  use ExUnit.Case, async: false

  alias Observatory.Mesh.DecisionLog

  setup do
    Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:messages")
    :ok
  end

  defp build_event(overrides \\ %{}) do
    defaults = %{
      id: "evt-#{System.unique_integer([:positive])}",
      source_app: "claude-code",
      session_id: "session-test-123",
      hook_event_type: :PreToolUse,
      payload: %{"tool_name" => "Bash", "tool_input" => %{"command" => "mix test"}},
      summary: nil,
      model_name: "claude-sonnet-4-6",
      tool_name: "Bash",
      tool_use_id: "tu-abc-123",
      cwd: "/Users/test/project",
      permission_mode: "default",
      duration_ms: nil,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    struct = Map.merge(defaults, overrides)
    # Return as a map with atom keys to simulate the Event struct
    struct
  end

  describe "event stream bridge" do
    test "transforms PreToolUse event into DecisionLog and broadcasts" do
      event = build_event()
      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})

      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      # Meta
      assert log.meta.trace_id == "session-test-123"
      assert log.meta.source_app == "claude-code"
      assert log.meta.tool_use_id == "tu-abc-123"
      assert log.meta.event_id == event.id

      # Identity
      assert log.identity.agent_id == "session-test-123"
      assert log.identity.agent_type == "claude-code"
      assert log.identity.model_name == "claude-sonnet-4-6"

      # Cognition
      assert log.cognition.intent == "tool_call:Bash"
      assert log.cognition.hook_event_type == "PreToolUse"

      # Action
      assert log.action.status == :pending
      assert log.action.tool_call == "Bash"
      assert log.action.cwd == "/Users/test/project"
      assert log.action.permission_mode == "default"
      assert log.action.payload == event.payload
    end

    test "transforms PostToolUse event with duration_ms" do
      event = build_event(%{
        hook_event_type: :PostToolUse,
        duration_ms: 342,
        summary: "Command completed successfully"
      })

      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "tool_result:Bash"
      assert log.cognition.hook_event_type == "PostToolUse"
      assert log.cognition.summary == "Command completed successfully"
      assert log.action.status == :success
      assert log.action.duration_ms == 342
    end

    test "transforms PostToolUseFailure as failure status" do
      event = build_event(%{hook_event_type: :PostToolUseFailure, duration_ms: 50})
      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "tool_failure:Bash"
      assert log.action.status == :failure
    end

    test "transforms SessionStart event" do
      event = build_event(%{hook_event_type: :SessionStart, tool_name: nil})
      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "session_start"
      assert log.cognition.hook_event_type == "SessionStart"
      assert log.action.status == :success
      assert log.control == nil
    end

    test "transforms SessionEnd as terminal event" do
      event = build_event(%{hook_event_type: :SessionEnd, tool_name: nil})
      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "session_end"
      assert log.control.is_terminal == true
    end

    test "transforms Stop as terminal event" do
      event = build_event(%{hook_event_type: :Stop, tool_name: nil})
      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "session_stop"
      assert log.control.is_terminal == true
    end

    test "transforms UserPromptSubmit event" do
      event = build_event(%{hook_event_type: :UserPromptSubmit, tool_name: nil})
      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "user_prompt"
      assert log.action.status == :success
    end

    test "transforms SubagentStart event" do
      event = build_event(%{hook_event_type: :SubagentStart, tool_name: nil})
      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "subagent_start"
    end

    test "transforms SubagentStop event" do
      event = build_event(%{hook_event_type: :SubagentStop, tool_name: nil})
      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "subagent_stop"
    end

    test "transforms PermissionRequest event" do
      event = build_event(%{hook_event_type: :PermissionRequest, tool_name: "Bash"})
      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "permission_request"
      assert log.action.status == :pending
    end

    test "transforms PreCompact event" do
      event = build_event(%{hook_event_type: :PreCompact, tool_name: nil})
      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "pre_compact"
    end

    test "preserves full payload map in action" do
      payload = %{"tool_name" => "Read", "tool_input" => %{"file_path" => "/etc/hosts"}, "custom_key" => "value"}
      event = build_event(%{payload: payload})
      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.action.payload == payload
      assert log.action.payload["custom_key"] == "value"
    end

    test "handles nil tool_name gracefully" do
      event = build_event(%{tool_name: nil, hook_event_type: :PreToolUse})
      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "tool_call:unknown"
      assert log.action.tool_call == nil
    end

    test "handles nil model_name" do
      event = build_event(%{model_name: nil})
      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.identity.model_name == nil
    end
  end

  describe "team tool intent mapping" do
    test "TeamCreate extracts team name into intent and cluster_id" do
      event = build_event(%{
        hook_event_type: :PreToolUse,
        tool_name: "TeamCreate",
        payload: %{"tool_input" => %{"team_name" => "my-project", "description" => "Working on X"}}
      })

      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "team_create:my-project"
      assert log.meta.cluster_id == "my-project"
    end

    test "TeamCreate PostToolUse maps to team_created" do
      event = build_event(%{
        hook_event_type: :PostToolUse,
        tool_name: "TeamCreate",
        payload: %{"tool_input" => %{"team_name" => "my-project"}}
      })

      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "team_created:my-project"
    end

    test "TeamDelete maps intent" do
      event = build_event(%{
        hook_event_type: :PreToolUse,
        tool_name: "TeamDelete",
        payload: %{"tool_input" => %{}}
      })

      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "team_delete"
    end

    test "SendMessage extracts recipient and type" do
      event = build_event(%{
        hook_event_type: :PreToolUse,
        tool_name: "SendMessage",
        payload: %{"tool_input" => %{"recipient" => "worker-1", "type" => "message", "content" => "hello"}}
      })

      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "send_message:worker-1"
    end

    test "SendMessage broadcast type" do
      event = build_event(%{
        hook_event_type: :PostToolUse,
        tool_name: "SendMessage",
        payload: %{"tool_input" => %{"type" => "broadcast", "content" => "attention all"}}
      })

      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "sent_broadcast:all"
    end

    test "SendMessage shutdown_request type" do
      event = build_event(%{
        hook_event_type: :PreToolUse,
        tool_name: "SendMessage",
        payload: %{"tool_input" => %{"type" => "shutdown_request", "recipient" => "worker-2"}}
      })

      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "send_shutdown_request:worker-2"
    end

    test "Task spawn extracts subagent_type" do
      event = build_event(%{
        hook_event_type: :PreToolUse,
        tool_name: "Task",
        payload: %{"tool_input" => %{"subagent_type" => "Explore", "prompt" => "find files"}}
      })

      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "spawn_agent:Explore"
    end

    test "Task spawn PostToolUse maps to agent_spawned" do
      event = build_event(%{
        hook_event_type: :PostToolUse,
        tool_name: "Task",
        payload: %{"tool_input" => %{"subagent_type" => "general-purpose"}}
      })

      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "agent_spawned:general-purpose"
    end

    test "TaskCreate maps intent" do
      event = build_event(%{
        hook_event_type: :PreToolUse,
        tool_name: "TaskCreate",
        payload: %{"tool_input" => %{"subject" => "Fix bug"}}
      })

      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "task_create"
    end

    test "TaskUpdate with status extracts status" do
      event = build_event(%{
        hook_event_type: :PreToolUse,
        tool_name: "TaskUpdate",
        payload: %{"tool_input" => %{"taskId" => "1", "status" => "completed"}}
      })

      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "task_update:completed"
    end

    test "TaskUpdate without status uses generic intent" do
      event = build_event(%{
        hook_event_type: :PreToolUse,
        tool_name: "TaskUpdate",
        payload: %{"tool_input" => %{"taskId" => "1", "owner" => "worker-1"}}
      })

      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "task_update"
    end

    test "EnterPlanMode maps intent" do
      event = build_event(%{
        hook_event_type: :PreToolUse,
        tool_name: "EnterPlanMode",
        payload: %{"tool_input" => %{}}
      })

      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "enter_plan_mode"
    end

    test "ExitPlanMode maps intent" do
      event = build_event(%{
        hook_event_type: :PreToolUse,
        tool_name: "ExitPlanMode",
        payload: %{"tool_input" => %{}}
      })

      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "exit_plan_mode"
    end

    test "EnterWorktree maps intent" do
      event = build_event(%{
        hook_event_type: :PostToolUse,
        tool_name: "EnterWorktree",
        payload: %{"tool_input" => %{"name" => "feature-x"}}
      })

      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "worktree_entered"
    end

    test "TaskList and TaskGet map intents" do
      event = build_event(%{
        hook_event_type: :PreToolUse,
        tool_name: "TaskList",
        payload: %{"tool_input" => %{}}
      })

      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.cognition.intent == "task_list"
    end

    test "team_name from payload populates cluster_id" do
      event = build_event(%{
        hook_event_type: :PreToolUse,
        tool_name: "Task",
        payload: %{"tool_input" => %{"team_name" => "build-team", "subagent_type" => "general-purpose"}}
      })

      Phoenix.PubSub.broadcast(Observatory.PubSub, "events:stream", {:new_event, event})
      assert_receive {:decision_log, %DecisionLog{} = log}, 1000

      assert log.meta.cluster_id == "build-team"
    end
  end
end
