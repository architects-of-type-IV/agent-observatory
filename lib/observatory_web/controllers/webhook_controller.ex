defmodule ObservatoryWeb.WebhookController do
  use ObservatoryWeb, :controller

  alias Observatory.Gateway.WebhookRouter

  def create(conn, %{"webhook_id" => webhook_id}) do
    with {:ok, signature} <- get_signature(conn),
         {:ok, body} <- read_body_once(conn),
         {:ok, secret} <- get_secret(webhook_id),
         true <- WebhookRouter.verify_signature(body, secret, signature) do
      conn
      |> put_status(:ok)
      |> json(%{"status" => "ok", "webhook_id" => webhook_id})
    else
      {:error, :missing_signature} ->
        conn
        |> put_status(:bad_request)
        |> json(%{"status" => "error", "reason" => "missing X-Observatory-Signature header"})

      false ->
        conn
        |> put_status(:unauthorized)
        |> json(%{"status" => "error", "reason" => "invalid signature"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{"status" => "error", "reason" => to_string(reason)})
    end
  end

  defp get_signature(conn) do
    case get_req_header(conn, "x-observatory-signature") do
      [sig | _] -> {:ok, sig}
      [] -> {:error, :missing_signature}
    end
  end

  defp read_body_once(conn) do
    case conn.assigns[:raw_body] do
      nil ->
        # Body already parsed by Phoenix -- reconstruct from params
        # For webhook verification, use the raw body cached by a plug or
        # fall back to JSON-encoding the params (minus path params)
        params = Map.drop(conn.params, ["webhook_id"])
        {:ok, Jason.encode!(params)}

      body ->
        {:ok, body}
    end
  end

  defp get_secret(webhook_id) do
    # Look up secret from config or registry. For now, use a config-based approach.
    secrets = Application.get_env(:observatory, :webhook_secrets, %{})

    case Map.get(secrets, webhook_id) do
      nil -> {:ok, Application.get_env(:observatory, :webhook_default_secret, "default-secret")}
      secret -> {:ok, secret}
    end
  end
end
