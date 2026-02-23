defmodule Observatory.Gateway.Channels.WebhookAdapter do
  @moduledoc """
  Delivers messages via the durable WebhookRouter (HTTP POST with HMAC-SHA256).
  This is an additive channel -- fires alongside the primary channel when configured.
  """

  @behaviour Observatory.Gateway.Channel

  @impl true
  def deliver(webhook_url, payload) when is_binary(webhook_url) do
    agent_id = payload[:agent_id] || payload["agent_id"] || "unknown"
    secret = payload[:webhook_secret] || payload["webhook_secret"] || default_secret()
    body = Jason.encode!(Map.drop(payload, [:webhook_secret, "webhook_secret", :agent_id, "agent_id"]))

    case Observatory.Gateway.WebhookRouter.enqueue(agent_id, webhook_url, body, secret) do
      {:ok, _delivery_id} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def available?(webhook_url) when is_binary(webhook_url) do
    String.starts_with?(webhook_url, "http")
  end

  defp default_secret do
    Application.get_env(:observatory, :webhook_default_secret, "observatory-default-secret")
  end
end
