defmodule Ichor.Infrastructure.WebhookRouter do
  @moduledoc "Webhook delivery API. Actual delivery runs via Oban (Workers.WebhookDeliveryWorker)."

  alias Ichor.Infrastructure.Workers.WebhookDeliveryWorker

  @spec compute_signature(String.t(), String.t()) :: String.t()
  def compute_signature(payload, secret) do
    "sha256=" <>
      (:crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower))
  end

  @spec verify_signature(String.t(), String.t(), String.t()) :: boolean()
  def verify_signature(payload, secret, provided_signature) do
    expected = compute_signature(payload, secret)
    Plug.Crypto.secure_compare(expected, provided_signature)
  end

  @spec enqueue_delivery(String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_delivery(delivery_id) do
    %{"delivery_id" => delivery_id}
    |> WebhookDeliveryWorker.new()
    |> Oban.insert()
  end
end
