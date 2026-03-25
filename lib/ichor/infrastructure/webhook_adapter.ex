defmodule Ichor.Infrastructure.WebhookAdapter do
  @moduledoc """
  Delivers messages via the durable webhook channel (HTTP POST with HMAC-SHA256).
  This is an additive channel -- fires alongside the primary channel when configured.
  """

  @behaviour Ichor.Infrastructure.Channel

  alias Ichor.Infrastructure.WebhookDelivery
  alias Ichor.Infrastructure.Workers.WebhookDeliveryWorker

  @impl true
  def channel_key, do: :webhook

  @impl true
  def deliver(webhook_url, payload) when is_binary(webhook_url) do
    agent_id = payload[:agent_id] || payload["agent_id"] || "unknown"
    secret = payload[:webhook_secret] || payload["webhook_secret"] || default_secret()

    body =
      Jason.encode!(Map.drop(payload, [:webhook_secret, "webhook_secret", :agent_id, "agent_id"]))

    signature = compute_signature(body, secret)

    case WebhookDelivery.enqueue(webhook_url, body, signature, agent_id) do
      {:ok, delivery} ->
        case enqueue_delivery(delivery.id) do
          {:ok, _job} ->
            {:ok, delivery.id}

          {:error, reason} ->
            WebhookDelivery.mark_dead(delivery, %{attempt_count: 0})
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def available?(webhook_url) when is_binary(webhook_url) do
    String.starts_with?(webhook_url, "http")
  end

  @doc "Compute HMAC-SHA256 signature for a payload."
  @spec compute_signature(String.t(), String.t()) :: String.t()
  def compute_signature(payload, secret) do
    "sha256=" <>
      (:crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower))
  end

  @doc "Verify that a provided signature matches the expected HMAC for the given payload and secret."
  @spec verify_signature(String.t(), String.t(), String.t()) :: boolean()
  def verify_signature(payload, secret, provided_signature) do
    expected = compute_signature(payload, secret)
    Plug.Crypto.secure_compare(expected, provided_signature)
  end

  defp enqueue_delivery(delivery_id) do
    %{"delivery_id" => delivery_id}
    |> WebhookDeliveryWorker.new()
    |> Oban.insert()
  end

  defp default_secret do
    Application.get_env(:ichor, :webhook_default_secret, "ichor-default-secret")
  end
end
