defmodule Ichor.Infrastructure.WebhookRouter do
  @moduledoc """
  Durable webhook delivery with exponential-backoff retry and dead-letter queue.
  Polls for pending/failed deliveries and attempts HTTP POST with HMAC-SHA256 signatures.
  """

  use GenServer

  require Logger

  alias Ichor.Infrastructure.WebhookDelivery

  @retry_schedule_seconds [30, 120, 600, 3600, 21_600]
  @poll_interval_ms 5_000
  @max_attempts 5

  @doc "Compute HMAC-SHA256 signature for payload verification."
  @spec compute_signature(String.t(), String.t()) :: String.t()
  def compute_signature(payload, secret) do
    "sha256=" <>
      (:crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower))
  end

  @doc "Timing-safe signature verification."
  @spec verify_signature(String.t(), String.t(), String.t()) :: boolean()
  def verify_signature(payload, secret, provided_signature) do
    expected = compute_signature(payload, secret)
    Plug.Crypto.secure_compare(expected, provided_signature)
  end

  @doc "Start the WebhookRouter GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    try do
      requeue_undelivered()
    catch
      kind, reason ->
        Logger.debug("WebhookRouter: skipping requeue on startup (#{kind}: #{inspect(reason)})")
    end

    Process.send_after(self(), :poll, @poll_interval_ms)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:poll, state) do
    try do
      WebhookDelivery.due_for_delivery!()
      |> Enum.each(&attempt_delivery/1)
    catch
      kind, reason ->
        Logger.debug("WebhookRouter: DB error during poll (#{kind}: #{inspect(reason)})")
    end

    Process.send_after(self(), :poll, @poll_interval_ms)
    {:noreply, state}
  end

  defp attempt_delivery(delivery) do
    headers = [{"x-ichor-signature", delivery.signature}]

    case delivery_fn().(delivery.target_url, body: delivery.payload, headers: headers) do
      {:ok, %{status: status}} when status >= 200 and status < 300 ->
        WebhookDelivery.mark_delivered(delivery)

      _error ->
        do_schedule_retry(delivery)
    end
  end

  defp delivery_fn do
    Application.get_env(:ichor, :webhook_delivery_fn, &Req.post/2)
  end

  defp do_schedule_retry(delivery) do
    new_attempt_count = delivery.attempt_count + 1

    if new_attempt_count >= @max_attempts do
      WebhookDelivery.mark_dead(delivery, %{attempt_count: new_attempt_count})
      Ichor.Signals.emit(:dead_letter, %{delivery: delivery})
    else
      delay_seconds = Enum.at(@retry_schedule_seconds, new_attempt_count - 1, 21_600)

      next_retry =
        DateTime.utc_now()
        |> DateTime.add(delay_seconds)
        |> DateTime.truncate(:second)

      WebhookDelivery.schedule_retry(delivery, %{
        attempt_count: new_attempt_count,
        next_retry_at: next_retry
      })
    end
  end

  defp requeue_undelivered do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    WebhookDelivery.due_for_delivery!()
    |> Enum.each(fn delivery ->
      WebhookDelivery.schedule_retry(delivery, %{
        attempt_count: delivery.attempt_count,
        next_retry_at: now
      })
    end)
  end
end
