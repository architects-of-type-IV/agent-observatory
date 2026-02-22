defmodule ObservatoryWeb.HeartbeatControllerTest do
  use ObservatoryWeb.ConnCase, async: false

  describe "POST /gateway/heartbeat" do
    test "returns 200 with valid params", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/gateway/heartbeat", %{"agent_id" => "agent-1", "cluster_id" => "cluster-a"})

      assert json_response(conn, 200) == %{"status" => "ok"}
    end

    test "returns 422 when agent_id is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/gateway/heartbeat", %{"cluster_id" => "cluster-a"})

      assert json_response(conn, 422)["status"] == "error"
    end

    test "returns 422 when cluster_id is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/gateway/heartbeat", %{"agent_id" => "agent-1"})

      assert json_response(conn, 422)["status"] == "error"
    end

    test "returns 422 when body is empty", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/gateway/heartbeat", %{})

      assert json_response(conn, 422)["status"] == "error"
    end
  end
end
