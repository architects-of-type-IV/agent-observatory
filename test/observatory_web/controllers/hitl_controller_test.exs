defmodule ObservatoryWeb.HITLControllerTest do
  use ObservatoryWeb.ConnCase, async: false

  alias Observatory.Gateway.HITLInterventionEvent
  alias Observatory.Repo

  @session_id "test-session-123"
  @operator_id "operator-42"

  defp auth_conn(conn) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-observatory-operator-id", @operator_id)
  end

  describe "operator auth" do
    test "returns 401 when x-observatory-operator-id header is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/gateway/sessions/#{@session_id}/pause", %{"agent_id" => "a1", "reason" => "test"})

      assert json_response(conn, 401) == %{"status" => "error", "reason" => "missing_operator_id"}
    end

    test "returns 401 when x-observatory-operator-id header is empty", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-observatory-operator-id", "  ")
        |> post("/gateway/sessions/#{@session_id}/pause", %{"agent_id" => "a1", "reason" => "test"})

      assert json_response(conn, 401) == %{"status" => "error", "reason" => "missing_operator_id"}
    end
  end

  describe "POST /gateway/sessions/:session_id/pause" do
    test "returns 200 on successful pause", %{conn: conn} do
      conn =
        conn
        |> auth_conn()
        |> post("/gateway/sessions/pause-ok-#{System.unique_integer([:positive])}/pause", %{
          "agent_id" => "agent-1",
          "reason" => "investigating anomaly"
        })

      assert json_response(conn, 200) == %{"status" => "ok"}
    end

    test "returns already_paused note on double pause", %{conn: conn} do
      sid = "double-pause-#{System.unique_integer([:positive])}"

      conn
      |> auth_conn()
      |> post("/gateway/sessions/#{sid}/pause", %{"agent_id" => "agent-1", "reason" => "first"})

      conn2 =
        build_conn()
        |> auth_conn()
        |> post("/gateway/sessions/#{sid}/pause", %{"agent_id" => "agent-1", "reason" => "second"})

      assert json_response(conn2, 200)["note"] == "already_paused"
    end

    test "returns 422 when agent_id is missing", %{conn: conn} do
      conn =
        conn
        |> auth_conn()
        |> post("/gateway/sessions/#{@session_id}/pause", %{"reason" => "test"})

      assert json_response(conn, 422)["status"] == "error"
    end

    test "returns 422 when reason is missing", %{conn: conn} do
      conn =
        conn
        |> auth_conn()
        |> post("/gateway/sessions/#{@session_id}/pause", %{"agent_id" => "agent-1"})

      assert json_response(conn, 422)["status"] == "error"
    end

    test "creates audit trail entry", %{conn: conn} do
      conn
      |> auth_conn()
      |> post("/gateway/sessions/pause-audit-sess/pause", %{"agent_id" => "agent-1", "reason" => "audit test"})

      events = Repo.all(HITLInterventionEvent)
      assert Enum.any?(events, fn e -> e.session_id == "pause-audit-sess" and e.action == "pause" end)
    end
  end

  describe "POST /gateway/sessions/:session_id/unpause" do
    test "returns not_paused when session is not paused", %{conn: conn} do
      conn =
        conn
        |> auth_conn()
        |> post("/gateway/sessions/unpause-fresh/unpause", %{"agent_id" => "agent-1"})

      assert json_response(conn, 200)["note"] == "not_paused"
    end

    test "returns flushed_count after unpausing a paused session", %{conn: conn} do
      # Pause first
      conn
      |> auth_conn()
      |> post("/gateway/sessions/unpause-test/pause", %{"agent_id" => "agent-1", "reason" => "test"})

      # Unpause
      conn2 =
        build_conn()
        |> auth_conn()
        |> post("/gateway/sessions/unpause-test/unpause", %{"agent_id" => "agent-1"})

      body = json_response(conn2, 200)
      assert body["status"] == "ok"
      assert is_integer(body["flushed_count"])
    end

    test "returns 422 when agent_id is missing", %{conn: conn} do
      conn =
        conn
        |> auth_conn()
        |> post("/gateway/sessions/#{@session_id}/unpause", %{})

      assert json_response(conn, 422)["status"] == "error"
    end
  end

  describe "POST /gateway/sessions/:session_id/rewrite" do
    test "returns not_found when trace_id does not exist", %{conn: conn} do
      conn =
        conn
        |> auth_conn()
        |> post("/gateway/sessions/#{@session_id}/rewrite", %{"trace_id" => "no-such-trace", "new_payload" => %{"foo" => "bar"}})

      assert json_response(conn, 404) == %{"status" => "error", "reason" => "not_found"}
    end

    test "returns 422 when trace_id is missing", %{conn: conn} do
      conn =
        conn
        |> auth_conn()
        |> post("/gateway/sessions/#{@session_id}/rewrite", %{"new_payload" => %{}})

      assert json_response(conn, 422)["status"] == "error"
    end

    test "returns 422 when new_payload is missing", %{conn: conn} do
      conn =
        conn
        |> auth_conn()
        |> post("/gateway/sessions/#{@session_id}/rewrite", %{"trace_id" => "t1"})

      assert json_response(conn, 422)["status"] == "error"
    end
  end

  describe "POST /gateway/sessions/:session_id/inject" do
    test "returns 200 on successful inject", %{conn: conn} do
      conn =
        conn
        |> auth_conn()
        |> post("/gateway/sessions/#{@session_id}/inject", %{"agent_id" => "agent-1", "payload" => %{"msg" => "hello"}})

      assert json_response(conn, 200) == %{"status" => "ok"}
    end

    test "returns 422 when agent_id is missing", %{conn: conn} do
      conn =
        conn
        |> auth_conn()
        |> post("/gateway/sessions/#{@session_id}/inject", %{"payload" => %{}})

      assert json_response(conn, 422)["status"] == "error"
    end

    test "returns 422 when payload is missing", %{conn: conn} do
      conn =
        conn
        |> auth_conn()
        |> post("/gateway/sessions/#{@session_id}/inject", %{"agent_id" => "agent-1"})

      assert json_response(conn, 422)["status"] == "error"
    end

    test "creates audit trail entry", %{conn: conn} do
      conn
      |> auth_conn()
      |> post("/gateway/sessions/inject-audit-sess/inject", %{"agent_id" => "agent-1", "payload" => %{"data" => 1}})

      events = Repo.all(HITLInterventionEvent)
      assert Enum.any?(events, fn e -> e.session_id == "inject-audit-sess" and e.action == "inject" end)
    end
  end
end
