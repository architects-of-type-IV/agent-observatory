defmodule Ichor.Infrastructure.Workers.WebhookDeliveryWorker do
  @moduledoc "Oban worker that delivers a single webhook with retry."
  use Oban.Worker, queue: :webhooks, max_attempts: 5

  require Logger

  alias Ichor.Infrastructure.WebhookDelivery

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => delivery_id}}) do
    case WebhookDelivery.get(delivery_id) do
      {:ok, delivery} -> attempt_delivery(delivery)
      {:error, _} -> :ok
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Exponential backoff: 30s, 120s, 600s, 3600s, 21600s
    Enum.at([30, 120, 600, 3_600, 21_600], attempt - 1, 21_600)
  end

  defp attempt_delivery(delivery) do
    headers = [{"x-ichor-signature", delivery.signature}]

    case delivery_fn().(delivery.target_url, body: delivery.payload, headers: headers) do
      {:ok, %{status: status}} when status >= 200 and status < 300 ->
        WebhookDelivery.mark_delivered(delivery)
        :ok

      error ->
        new_count = delivery.attempt_count + 1

        if new_count >= 5 do
          WebhookDelivery.mark_dead(delivery, %{attempt_count: new_count})
          Ichor.Signals.emit(:dead_letter, %{delivery: delivery})
          :ok
        else
          WebhookDelivery.schedule_retry(delivery, %{
            attempt_count: new_count,
            next_retry_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })

          {:error, "delivery failed: #{inspect(error)}"}
        end
    end
  end

  defp delivery_fn do
    Application.get_env(:ichor, :webhook_delivery_fn, &Req.post/2)
  end
end
