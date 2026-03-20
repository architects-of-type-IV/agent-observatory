defmodule Ichor.Infrastructure.WebhookAdapter do
  @moduledoc """
  Delivers messages via the durable WebhookRouter (HTTP POST with HMAC-SHA256).
  This is an additive channel -- fires alongside the primary channel when configured.
  """

  @behaviour Ichor.Infrastructure.Channel

  alias Ichor.Infrastructure.{WebhookDelivery, WebhookRouter}

  @impl true
  def channel_key, do: :webhook

  @impl true
  def deliver(webhook_url, payload) when is_binary(webhook_url) do
    agent_id = payload[:agent_id] || payload["agent_id"] || "unknown"
    secret = payload[:webhook_secret] || payload["webhook_secret"] || default_secret()

    body =
      Jason.encode!(Map.drop(payload, [:webhook_secret, "webhook_secret", :agent_id, "agent_id"]))

    signature = WebhookRouter.compute_signature(body, secret)

    case WebhookDelivery.enqueue(webhook_url, body, signature, agent_id) do
      {:ok, delivery} -> {:ok, delivery.id}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def available?(webhook_url) when is_binary(webhook_url) do
    String.starts_with?(webhook_url, "http")
  end

  defp default_secret do
    Application.get_env(:ichor, :webhook_default_secret, "ichor-default-secret")
  end
end
