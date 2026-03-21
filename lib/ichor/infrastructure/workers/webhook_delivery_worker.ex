defmodule Ichor.Infrastructure.Workers.WebhookDeliveryWorker do
  @moduledoc "Oban worker that delivers a single webhook with retry."
  use Oban.Worker, queue: :webhooks, max_attempts: 5

  require Logger

  alias Ichor.Infrastructure.WebhookDelivery

  @backoff_seconds [30, 120, 600, 3_600, 21_600]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => delivery_id}, attempt: attempt}) do
    case WebhookDelivery.get(delivery_id) do
      {:ok, %{status: :delivered}} -> :ok
      {:ok, %{status: :dead}} -> :ok
      {:ok, delivery} -> attempt_delivery(delivery, attempt)
      {:error, _} -> :ok
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    Enum.at(@backoff_seconds, attempt - 1, 21_600)
  end

  defp attempt_delivery(delivery, attempt) do
    headers = [{"x-ichor-signature", delivery.signature}]

    case delivery_fn().(delivery.target_url, body: delivery.payload, headers: headers) do
      {:ok, %{status: status}} when status >= 200 and status < 300 ->
        case WebhookDelivery.mark_delivered(delivery) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, "mark_delivered failed: #{inspect(reason)}"}
        end

      error ->
        new_count = delivery.attempt_count + 1

        if new_count >= 5 do
          case WebhookDelivery.mark_dead(delivery, %{attempt_count: new_count}) do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, "mark_dead failed: #{inspect(reason)}"}
          end
        else
          next_backoff = Enum.at(@backoff_seconds, attempt - 1, 21_600)

          next_retry =
            DateTime.utc_now() |> DateTime.add(next_backoff) |> DateTime.truncate(:second)

          case WebhookDelivery.schedule_retry(delivery, %{
                 attempt_count: new_count,
                 next_retry_at: next_retry
               }) do
            {:ok, _} -> {:error, "delivery failed: #{inspect(error)}"}
            {:error, reason} -> {:error, "schedule_retry failed: #{inspect(reason)}"}
          end
        end
    end
  end

  defp delivery_fn do
    Application.get_env(:ichor, :webhook_delivery_fn, &Req.post/2)
  end
end
