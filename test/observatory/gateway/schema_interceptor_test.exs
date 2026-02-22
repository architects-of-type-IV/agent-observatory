defmodule Observatory.Gateway.SchemaInterceptorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Observatory.Gateway.EntropyTracker
  alias Observatory.Gateway.HITLRelay
  alias Observatory.Gateway.SchemaInterceptor
  alias Observatory.Mesh.DecisionLog

  @valid_params %{
    "meta" => %{
      "trace_id" => "550e8400-e29b-41d4-a716-446655440000",
      "timestamp" => "2026-02-22T12:00:00Z"
    },
    "identity" => %{
      "agent_id" => "agent-001",
      "agent_type" => "reasoning",
      "capability_version" => "1.0.0"
    },
    "cognition" => %{
      "intent" => "classify_input",
      "reasoning_chain" => ["step 1", "step 2"],
      "confidence_score" => 0.95,
      "strategy_used" => "CoT",
      "entropy_score" => 0.3
    },
    "action" => %{
      "status" => "success",
      "tool_call" => "classify",
      "tool_input" => ~s({"text": "hello"}),
      "tool_output_summary" => "classified as greeting"
    },
    "state_delta" => %{
      "added_to_memory" => ["greeting detected"],
      "tokens_consumed" => 150,
      "cumulative_session_cost" => 0.002
    },
    "control" => %{
      "hitl_required" => false,
      "interrupt_signal" => nil,
      "is_terminal" => false
    }
  }

  describe "module boundary" do
    @tag :boundary
    test "SchemaInterceptor @moduledoc documents the module boundary constraint" do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} =
        Code.fetch_docs(Observatory.Gateway.SchemaInterceptor)

      assert moduledoc =~ "ObservatoryWeb"
      assert moduledoc =~ "PubSub"
    end

    @tag :boundary
    test "SchemaInterceptor source file contains no ObservatoryWeb alias or import outside moduledoc" do
      source = File.read!("lib/observatory/gateway/schema_interceptor.ex")

      # Strip the moduledoc block (content between first triple-quote pair after @moduledoc)
      stripped =
        Regex.replace(~r/@moduledoc\s+""".*?"""/s, source, "@moduledoc \"\"\"(stripped)\"\"\"")

      refute stripped =~ ~r/alias ObservatoryWeb|import ObservatoryWeb/
    end
  end

  describe "validate/1" do
    @tag :validate
    test "returns {:ok, %DecisionLog{}} for a fully valid params map" do
      assert {:ok, %DecisionLog{}} = SchemaInterceptor.validate(@valid_params)
    end

    @tag :validate
    test "returns {:error, changeset} when meta.timestamp is absent" do
      params = put_in(@valid_params, ["meta", "timestamp"], nil)

      assert {:error, %Ecto.Changeset{valid?: false} = changeset} =
               SchemaInterceptor.validate(params)

      meta_changeset = changeset.changes.meta
      assert {:timestamp, {"can't be blank", [validation: :required]}} in meta_changeset.errors
    end

    @tag :validate
    test "completes synchronously with no async primitives in source" do
      source = File.read!("lib/observatory/gateway/schema_interceptor.ex")

      # Strip comment lines before checking — comments document constraints but don't introduce primitives
      non_comment_lines =
        source
        |> String.split("\n")
        |> Enum.reject(&String.match?(&1, ~r/^\s*#/))
        |> Enum.join("\n")

      refute non_comment_lines =~ ~r/Task\.(start|async)|GenServer\.call|Process\.spawn|:erlang\.spawn/
    end
  end

  describe "build_violation_event/3" do
    setup do
      # Construct an invalid changeset: meta present but missing required fields
      changeset = DecisionLog.changeset(%DecisionLog{}, %{"meta" => %{}})
      refute changeset.valid?
      %{changeset: changeset}
    end

    @tag :violation_event
    test "returns a plain map with all six required keys", %{changeset: changeset} do
      params = %{"identity" => %{"agent_id" => "agent-007", "capability_version" => "2.0.0"}}

      event = SchemaInterceptor.build_violation_event(changeset, params, nil)

      assert is_map(event)
      assert Map.has_key?(event, "event_type")
      assert Map.has_key?(event, "timestamp")
      assert Map.has_key?(event, "agent_id")
      assert Map.has_key?(event, "capability_version")
      assert Map.has_key?(event, "violation_reason")
      assert Map.has_key?(event, "raw_payload_hash")

      assert event["event_type"] == "schema_violation"
      assert event["agent_id"] == "agent-007"
      assert event["capability_version"] == "2.0.0"
      assert is_binary(event["violation_reason"])
      assert is_binary(event["timestamp"])
    end

    @tag :violation_event
    test "defaults agent_id to unknown when identity block is absent", %{changeset: changeset} do
      event = SchemaInterceptor.build_violation_event(changeset, %{}, nil)

      assert event["agent_id"] == "unknown"
      assert event["capability_version"] == "unknown"
    end

    @tag :violation_event
    test "raw_payload_hash starts with sha256: and is 71 characters", %{changeset: changeset} do
      raw_body = ~s({"some": "payload"})

      event = SchemaInterceptor.build_violation_event(changeset, %{}, raw_body)

      assert String.starts_with?(event["raw_payload_hash"], "sha256:")
      # sha256: (7 chars) + 64 hex chars = 71
      assert String.length(event["raw_payload_hash"]) == 71
    end

    @tag :violation_event
    test "does not include a raw_payload key in the event map", %{changeset: changeset} do
      raw_body = ~s({"secret": "data"})
      params = %{"identity" => %{"agent_id" => "a1"}}

      event = SchemaInterceptor.build_violation_event(changeset, params, raw_body)

      refute Map.has_key?(event, "raw_payload")
      refute Map.has_key?(event, :raw_payload)
    end

    @tag :violation_event
    test "falls back to JSON hash when raw_body is nil", %{changeset: changeset} do
      params = %{"identity" => %{"agent_id" => "a1"}}

      event_nil = SchemaInterceptor.build_violation_event(changeset, params, nil)
      event_empty = SchemaInterceptor.build_violation_event(changeset, params, "")

      # Both nil and empty string should use JSON fallback, producing the same hash
      assert String.starts_with?(event_nil["raw_payload_hash"], "sha256:")
      assert String.starts_with?(event_empty["raw_payload_hash"], "sha256:")
      assert event_nil["raw_payload_hash"] == event_empty["raw_payload_hash"]
    end

    @tag :violation_event
    test "does not log params or raw body during rejection", %{changeset: changeset} do
      sentinel_body = "SENTINEL_RAW_BODY_12345"
      params = %{"identity" => %{"agent_id" => "SENTINEL_AGENT_ID_67890"}}

      log =
        capture_log(fn ->
          SchemaInterceptor.build_violation_event(changeset, params, sentinel_body)
        end)

      refute log =~ "SENTINEL_RAW_BODY_12345"
      refute log =~ "SENTINEL_AGENT_ID_67890"
    end
  end

  describe "PubSub broadcast" do
    @tag :pubsub
    test "broadcast on gateway:violations delivers {:schema_violation, event} to subscribers" do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:violations")

      event = %{"event_type" => "schema_violation", "agent_id" => "test-agent"}
      Phoenix.PubSub.broadcast(Observatory.PubSub, "gateway:violations", {:schema_violation, event})

      assert_receive {:schema_violation, ^event}, 1000
    end

    @tag :pubsub
    test "broadcast uses :schema_violation atom as the message tuple key" do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:violations")

      event = %{"event_type" => "schema_violation"}
      Phoenix.PubSub.broadcast(Observatory.PubSub, "gateway:violations", {:schema_violation, event})

      assert_receive {:schema_violation, _}, 1000
      refute_receive {"schema_violation", _}, 100
    end
  end

  describe "maybe_auto_pause/1" do
    setup do
      :ets.delete_all_objects(:hitl_buffer)
      :ok
    end

    defp build_log_with_hitl(opts) do
      hitl_required = Keyword.get(opts, :hitl_required, false)
      trace_id = Keyword.get(opts, :trace_id, "trace-#{System.unique_integer([:positive])}")
      agent_id = Keyword.get(opts, :agent_id, "agent-1")

      %DecisionLog{
        meta: %DecisionLog.Meta{
          trace_id: trace_id,
          timestamp: DateTime.utc_now()
        },
        identity: %DecisionLog.Identity{
          agent_id: agent_id,
          agent_type: "worker",
          capability_version: "1.0.0"
        },
        cognition: %DecisionLog.Cognition{
          intent: "test_intent"
        },
        action: %DecisionLog.Action{
          status: :success,
          tool_call: "test_tool"
        },
        control: %DecisionLog.Control{
          hitl_required: hitl_required
        }
      }
    end

    test "returns {:paused, log} when hitl_required is true" do
      log = build_log_with_hitl(hitl_required: true)

      assert {:paused, ^log} = SchemaInterceptor.maybe_auto_pause(log)
    end

    test "pauses the session via HITLRelay when hitl_required is true" do
      trace_id = "auto-pause-#{System.unique_integer([:positive])}"
      log = build_log_with_hitl(hitl_required: true, trace_id: trace_id)

      SchemaInterceptor.maybe_auto_pause(log)

      assert :paused = HITLRelay.session_status(trace_id)
    end

    test "buffers the message when hitl_required is true" do
      trace_id = "buffer-ap-#{System.unique_integer([:positive])}"
      log = build_log_with_hitl(hitl_required: true, trace_id: trace_id)

      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:messages")

      SchemaInterceptor.maybe_auto_pause(log)

      # Unpause to flush the buffer and verify the message was buffered
      {:ok, 1} = HITLRelay.unpause(trace_id, "operator", "dashboard_operator")

      assert_receive {:decision_log, ^log}
    end

    test "returns {:normal, log} when hitl_required is false" do
      log = build_log_with_hitl(hitl_required: false)

      assert {:normal, ^log} = SchemaInterceptor.maybe_auto_pause(log)
    end

    test "returns {:normal, log} when control is nil" do
      log = %DecisionLog{control: nil}

      assert {:normal, ^log} = SchemaInterceptor.maybe_auto_pause(log)
    end

    test "returns {:paused, log} even when meta is nil (no session_id)" do
      log = %DecisionLog{
        meta: nil,
        identity: %DecisionLog.Identity{
          agent_id: "agent-1",
          agent_type: "worker",
          capability_version: "1.0.0"
        },
        control: %DecisionLog.Control{hitl_required: true}
      }

      assert {:paused, ^log} = SchemaInterceptor.maybe_auto_pause(log)
    end
  end

  describe "EntropyTracker call contract (3.6.2)" do
    setup do
      start_supervised!({EntropyTracker, []})
      :ok
    end

    @tag :entropy_contract
    test "invalid message does not call EntropyTracker" do
      session = "sess-contract-#{System.unique_integer([:positive])}"

      # identity is present but missing required agent_id -> validation failure
      invalid_params = %{
        "meta" => %{"trace_id" => session, "timestamp" => "2026-02-22T12:00:00Z"},
        "identity" => %{"agent_type" => "reasoning", "capability_version" => "1.0.0"}
      }

      assert {:error, _changeset} = SchemaInterceptor.validate_and_enrich(invalid_params)

      # Process a valid message for the same session — window should contain only this one entry
      valid_params = put_in(@valid_params, ["meta", "trace_id"], session)
      assert {:ok, _log} = SchemaInterceptor.validate_and_enrich(valid_params)

      window = EntropyTracker.get_window(session)
      assert length(window) == 1
    end
  end
end
