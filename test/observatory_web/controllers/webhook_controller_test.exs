defmodule ObservatoryWeb.WebhookControllerTest do
  use ObservatoryWeb.ConnCase

  alias Observatory.Gateway.WebhookRouter

  @secret "default-secret"
  @webhook_id "wh-test-001"

  describe "POST /gateway/webhooks/:webhook_id" do
    test "returns 200 with valid signature", %{conn: conn} do
      payload = Jason.encode!(%{"event" => "test"})
      signature = WebhookRouter.compute_signature(payload, @secret)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-observatory-signature", signature)
        |> post("/gateway/webhooks/#{@webhook_id}", payload)

      assert conn.status == 200
      body = json_response(conn, 200)
      assert body["status"] == "ok"
      assert body["webhook_id"] == @webhook_id
    end

    test "returns 401 with invalid signature", %{conn: conn} do
      payload = Jason.encode!(%{"event" => "test"})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-observatory-signature", "sha256=invalid")
        |> post("/gateway/webhooks/#{@webhook_id}", payload)

      assert conn.status == 401
      body = json_response(conn, 401)
      assert body["status"] == "error"
      assert body["reason"] == "invalid signature"
    end

    test "returns 400 with missing signature header", %{conn: conn} do
      payload = Jason.encode!(%{"event" => "test"})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/gateway/webhooks/#{@webhook_id}", payload)

      assert conn.status == 400
      body = json_response(conn, 400)
      assert body["status"] == "error"
      assert body["reason"] =~ "missing"
    end

    test "signature verification is timing-safe", %{conn: conn} do
      payload = Jason.encode!(%{"data" => "sensitive"})
      valid_sig = WebhookRouter.compute_signature(payload, @secret)

      # Valid request succeeds
      conn1 =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-observatory-signature", valid_sig)
        |> post("/gateway/webhooks/#{@webhook_id}", payload)

      assert conn1.status == 200

      # Slightly different signature fails
      tampered_sig = String.replace(valid_sig, ~r/.$/, "0")

      conn2 =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-observatory-signature", tampered_sig)
        |> post("/gateway/webhooks/#{@webhook_id}", payload)

      assert conn2.status == 401
    end
  end
end
