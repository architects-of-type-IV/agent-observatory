defmodule Observatory.Gateway.WebhookRouter do
  @moduledoc """
  Durable webhook delivery with exponential-backoff retry and dead-letter queue.
  Polls for pending/failed deliveries and attempts HTTP POST with HMAC-SHA256 signatures.
  """

  use GenServer

  require Logger

  import Ecto.Query

  alias Observatory.Gateway.WebhookDelivery
  alias Observatory.Repo

  @retry_schedule_seconds [30, 120, 600, 3600, 21_600]
  @poll_interval_ms 5_000
  @max_attempts 5

  # ── Client API ──────────────────────────────────────────────────────

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Enqueue a webhook delivery with HMAC-SHA256 signature."
  def enqueue(agent_id, target_url, payload, secret) do
    signature = compute_signature(payload, secret)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      agent_id: agent_id,
      target_url: target_url,
      payload: payload,
      signature: signature,
      status: "pending",
      attempt_count: 0,
      next_retry_at: now,
      inserted_at: now
    }

    case Repo.insert(WebhookDelivery.changeset(%WebhookDelivery{}, attrs)) do
      {:ok, delivery} -> {:ok, delivery.id}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "List all dead-letter deliveries for an agent."
  def list_dead_letters(agent_id) do
    WebhookDelivery
    |> where([d], d.agent_id == ^agent_id and d.status == "dead")
    |> Repo.all()
  end

  @doc "List all dead-letter deliveries across all agents."
  def list_all_dead_letters do
    WebhookDelivery
    |> where([d], d.status == "dead")
    |> Repo.all()
  rescue
    _ -> []
  end

  @doc "Compute HMAC-SHA256 signature for payload verification."
  def compute_signature(payload, secret) do
    "sha256=" <>
      (:crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower))
  end

  @doc "Timing-safe signature verification."
  def verify_signature(payload, secret, provided_signature) do
    expected = compute_signature(payload, secret)
    Plug.Crypto.secure_compare(expected, provided_signature)
  end

  # ── Server Callbacks ────────────────────────────────────────────────

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
      now = DateTime.utc_now()

      deliveries =
        WebhookDelivery
        |> where([d], d.status in ["pending", "failed"] and d.next_retry_at <= ^now)
        |> limit(5)
        |> Repo.all()

      Enum.each(deliveries, &attempt_delivery/1)
    catch
      kind, reason ->
        Logger.debug("WebhookRouter: DB error during poll (#{kind}: #{inspect(reason)})")
    end

    Process.send_after(self(), :poll, @poll_interval_ms)
    {:noreply, state}
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp attempt_delivery(delivery) do
    headers = [{"x-observatory-signature", delivery.signature}]

    case delivery_fn().(delivery.target_url, body: delivery.payload, headers: headers) do
      {:ok, %{status: status}} when status >= 200 and status < 300 ->
        delivery
        |> WebhookDelivery.changeset(%{status: "delivered"})
        |> Repo.update()

      _error ->
        schedule_retry(delivery)
    end
  end

  defp delivery_fn do
    Application.get_env(:observatory, :webhook_delivery_fn, &Req.post/2)
  end

  defp schedule_retry(delivery) do
    new_attempt_count = delivery.attempt_count + 1

    if new_attempt_count >= @max_attempts do
      delivery
      |> WebhookDelivery.changeset(%{status: "dead", attempt_count: new_attempt_count})
      |> Repo.update()

      Phoenix.PubSub.broadcast(
        Observatory.PubSub,
        "gateway:dlq",
        {:dead_letter, delivery}
      )
    else
      delay_seconds = Enum.at(@retry_schedule_seconds, new_attempt_count - 1, 21_600)
      next_retry = DateTime.utc_now() |> DateTime.add(delay_seconds) |> DateTime.truncate(:second)

      delivery
      |> WebhookDelivery.changeset(%{
        status: "failed",
        attempt_count: new_attempt_count,
        next_retry_at: next_retry
      })
      |> Repo.update()
    end
  end

  defp requeue_undelivered do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    WebhookDelivery
    |> where([d], d.status in ["pending", "failed"])
    |> Repo.update_all(set: [next_retry_at: now])
  end
end
