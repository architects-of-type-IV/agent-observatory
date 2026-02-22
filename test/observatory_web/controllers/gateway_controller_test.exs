defmodule ObservatoryWeb.GatewayControllerTest do
  use ObservatoryWeb.ConnCase

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

  @tag :routing
  test "POST /gateway/message (singular) returns HTTP 404", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/gateway/message", Jason.encode!(%{}))

    assert conn.status == 404
  end

  @tag :routing
  test "POST /gateway/messages with valid JSON body calls SchemaInterceptor.validate/1 as first action",
       %{conn: conn} do
    # identity present but missing all required fields triggers validation failure,
    # proving validate/1 runs as the first action (otherwise response would not be 422)
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/gateway/messages", Jason.encode!(%{"identity" => %{}}))

    assert conn.status == 422
  end

  @tag :rejection
  test "POST /gateway/messages missing identity.agent_id returns HTTP 422 with structured body",
       %{conn: conn} do
    params =
      put_in(@valid_params, ["identity", "agent_id"], nil)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/gateway/messages", Jason.encode!(params))

    assert conn.status == 422
    body = json_response(conn, 422)
    assert body["status"] == "rejected"
    assert body["reason"] == "schema_violation"
    assert is_binary(body["detail"])
    assert String.contains?(body["detail"], "agent_id")
    assert Map.has_key?(body, "trace_id")
  end

  @tag :rejection
  test "POST /gateway/messages schema violation returns 422 not 400", %{conn: conn} do
    # meta present but missing required trace_id triggers a schema violation
    params = put_in(@valid_params, ["meta", "trace_id"], nil)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/gateway/messages", Jason.encode!(params))

    assert conn.status == 422
    assert conn.status != 400
  end

  @tag :rejection
  test "422 response body trace_id field is null", %{conn: conn} do
    # identity present but empty triggers validation failure
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/gateway/messages", Jason.encode!(%{"identity" => %{}}))

    body = json_response(conn, 422)
    assert Map.has_key?(body, "trace_id")
    assert body["trace_id"] == nil
  end

  describe "topology broadcast" do
    @tag :topology
    test "POST /gateway/messages with invalid payload broadcasts {:node_state_update, update} on gateway:topology",
         %{conn: conn} do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:topology")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/gateway/messages", Jason.encode!(%{"identity" => %{}}))

      assert conn.status == 422

      assert_receive {:node_state_update, update}, 1000
      assert update.state == :schema_violation
      assert update.clear_after_ms == 30_000
      assert is_binary(update.agent_id)
    end

    @tag :topology
    test "topology broadcast fires on rejection with :schema_violation state atom not string",
         %{conn: conn} do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:topology")

      _conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/gateway/messages", Jason.encode!(%{"identity" => %{}}))

      assert_receive {:node_state_update, update}, 1000
      assert update.state == :schema_violation
      assert is_atom(update.state)
      assert update.state != "schema_violation"
    end

    @tag :topology
    test "topology broadcast does NOT fire on successful validation",
         %{conn: conn} do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:topology")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/gateway/messages", Jason.encode!(@valid_params))

      assert conn.status == 202
      refute_receive {:node_state_update, %{state: :schema_violation}}, 500
    end
  end

  describe "success path" do
    @tag :success
    test "POST /gateway/messages with valid payload returns HTTP 202 with trace_id",
         %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/gateway/messages", Jason.encode!(@valid_params))

      assert conn.status == 202
      body = json_response(conn, 202)
      assert body["status"] == "accepted"
      assert body["trace_id"] == "550e8400-e29b-41d4-a716-446655440000"
    end

    @tag :success
    test "POST /gateway/messages with valid payload broadcasts {:decision_log, log} on gateway:messages",
         %{conn: conn} do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:messages")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/gateway/messages", Jason.encode!(@valid_params))

      assert conn.status == 202

      assert_receive {:decision_log, received_log}, 1000
      assert %Observatory.Mesh.DecisionLog{} = received_log
      assert received_log.meta.trace_id == "550e8400-e29b-41d4-a716-446655440000"
    end

    @tag :success
    test "schema-rejected payload never broadcasts on gateway:messages",
         %{conn: conn} do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:messages")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/gateway/messages", Jason.encode!(%{"identity" => %{}}))

      assert conn.status == 422
      refute_receive {:decision_log, _}, 500
    end
  end

  describe "PubSub broadcast" do
    @tag :pubsub
    test "POST /gateway/messages with invalid payload broadcasts {:schema_violation, event} on gateway:violations",
         %{conn: conn} do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:violations")

      # identity present but missing required fields triggers 422
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/gateway/messages", Jason.encode!(%{"identity" => %{}}))

      assert conn.status == 422
      body = json_response(conn, 422)
      assert body["status"] == "rejected"
      assert body["reason"] == "schema_violation"

      # Task.start is async -- wait for broadcast
      assert_receive {:schema_violation, event}, 1000
      assert event["event_type"] == "schema_violation"
      assert is_binary(event["raw_payload_hash"])
      assert String.starts_with?(event["raw_payload_hash"], "sha256:")
      refute Map.has_key?(event, "raw_payload")
    end
  end
end
