defmodule Observatory.Gateway.WebhookRouterTest do
  use Observatory.DataCase

  alias Observatory.Gateway.WebhookDelivery
  alias Observatory.Gateway.WebhookRouter

  @secret "test-secret-key"

  describe "compute_signature/2" do
    test "returns sha256= prefixed HMAC hex" do
      sig = WebhookRouter.compute_signature("hello", @secret)
      assert String.starts_with?(sig, "sha256=")
      # Remove prefix, should be valid hex
      hex = String.replace_prefix(sig, "sha256=", "")
      assert String.match?(hex, ~r/^[0-9a-f]+$/)
    end

    test "same input produces same signature" do
      sig1 = WebhookRouter.compute_signature("payload", @secret)
      sig2 = WebhookRouter.compute_signature("payload", @secret)
      assert sig1 == sig2
    end

    test "different payloads produce different signatures" do
      sig1 = WebhookRouter.compute_signature("payload-a", @secret)
      sig2 = WebhookRouter.compute_signature("payload-b", @secret)
      refute sig1 == sig2
    end
  end

  describe "verify_signature/3" do
    test "returns true for valid signature" do
      payload = "test-body"
      sig = WebhookRouter.compute_signature(payload, @secret)
      assert WebhookRouter.verify_signature(payload, @secret, sig)
    end

    test "returns false for tampered payload" do
      sig = WebhookRouter.compute_signature("original", @secret)
      refute WebhookRouter.verify_signature("tampered", @secret, sig)
    end

    test "returns false for wrong secret" do
      payload = "test-body"
      sig = WebhookRouter.compute_signature(payload, @secret)
      refute WebhookRouter.verify_signature(payload, "wrong-secret", sig)
    end

    test "returns false for garbage signature" do
      refute WebhookRouter.verify_signature("body", @secret, "sha256=deadbeef")
    end
  end

  describe "enqueue/4" do
    test "creates a pending delivery and returns id" do
      {:ok, id} = WebhookRouter.enqueue("agent-1", "https://example.com/hook", "{}", @secret)
      assert is_binary(id)

      delivery = Repo.get!(WebhookDelivery, id)
      assert delivery.status == "pending"
      assert delivery.attempt_count == 0
      assert delivery.agent_id == "agent-1"
      assert delivery.target_url == "https://example.com/hook"
      assert delivery.payload == "{}"
      assert String.starts_with?(delivery.signature, "sha256=")
      assert delivery.inserted_at != nil
    end

    test "returns error on invalid params" do
      {:error, changeset} = WebhookRouter.enqueue("agent-1", nil, "{}", @secret)
      refute changeset.valid?
    end
  end

  describe "list_dead_letters/1" do
    test "returns only dead deliveries for the given agent" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Dead delivery for agent-1
      Repo.insert!(%WebhookDelivery{
        target_url: "https://example.com/hook",
        payload: "{}",
        agent_id: "agent-1",
        status: "dead",
        attempt_count: 5,
        inserted_at: now
      })

      # Pending delivery for agent-1 (should not appear)
      Repo.insert!(%WebhookDelivery{
        target_url: "https://example.com/hook2",
        payload: "{}",
        agent_id: "agent-1",
        status: "pending",
        attempt_count: 0,
        next_retry_at: now,
        inserted_at: now
      })

      # Dead delivery for agent-2 (should not appear)
      Repo.insert!(%WebhookDelivery{
        target_url: "https://example.com/hook3",
        payload: "{}",
        agent_id: "agent-2",
        status: "dead",
        attempt_count: 5,
        inserted_at: now
      })

      dead = WebhookRouter.list_dead_letters("agent-1")
      assert length(dead) == 1
      assert hd(dead).agent_id == "agent-1"
      assert hd(dead).status == "dead"
    end

    test "returns empty list when no dead letters" do
      assert WebhookRouter.list_dead_letters("nonexistent") == []
    end
  end

  describe "poll cycle - delivery success" do
    test "marks delivery as delivered on 2xx response" do
      # Configure mock delivery function
      test_pid = self()

      mock_fn = fn _url, _opts ->
        send(test_pid, :delivery_attempted)
        {:ok, %{status: 200}}
      end

      Application.put_env(:observatory, :webhook_delivery_fn, mock_fn)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      delivery =
        Repo.insert!(%WebhookDelivery{
          target_url: "https://example.com/hook",
          payload: "test-payload",
          signature: "sha256=abc",
          agent_id: "agent-1",
          status: "pending",
          attempt_count: 0,
          next_retry_at: now,
          inserted_at: now
        })

      # Trigger poll
      send(Process.whereis(WebhookRouter), :poll)

      assert_receive :delivery_attempted, 5000

      # Allow async processing
      Process.sleep(100)

      updated = Repo.get!(WebhookDelivery, delivery.id)
      assert updated.status == "delivered"
    after
      Application.delete_env(:observatory, :webhook_delivery_fn)
    end
  end

  describe "poll cycle - delivery failure and retry" do
    test "increments attempt_count and sets status to failed on error" do
      test_pid = self()

      mock_fn = fn _url, _opts ->
        send(test_pid, :delivery_attempted)
        {:ok, %{status: 500}}
      end

      Application.put_env(:observatory, :webhook_delivery_fn, mock_fn)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      delivery =
        Repo.insert!(%WebhookDelivery{
          target_url: "https://example.com/hook",
          payload: "test-payload",
          signature: "sha256=abc",
          agent_id: "agent-1",
          status: "pending",
          attempt_count: 0,
          next_retry_at: now,
          inserted_at: now
        })

      send(Process.whereis(WebhookRouter), :poll)

      assert_receive :delivery_attempted, 5000
      Process.sleep(100)

      updated = Repo.get!(WebhookDelivery, delivery.id)
      assert updated.status == "failed"
      assert updated.attempt_count == 1
      assert updated.next_retry_at != nil
    after
      Application.delete_env(:observatory, :webhook_delivery_fn)
    end
  end

  describe "poll cycle - dead letter after max attempts" do
    test "marks as dead and broadcasts to gateway:dlq after 5 failures" do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:dlq")

      test_pid = self()

      mock_fn = fn _url, _opts ->
        send(test_pid, :delivery_attempted)
        {:ok, %{status: 500}}
      end

      Application.put_env(:observatory, :webhook_delivery_fn, mock_fn)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      delivery =
        Repo.insert!(%WebhookDelivery{
          target_url: "https://example.com/hook",
          payload: "test-payload",
          signature: "sha256=abc",
          agent_id: "agent-1",
          status: "failed",
          attempt_count: 4,
          next_retry_at: now,
          inserted_at: now
        })

      send(Process.whereis(WebhookRouter), :poll)

      assert_receive :delivery_attempted, 5000
      Process.sleep(100)

      updated = Repo.get!(WebhookDelivery, delivery.id)
      assert updated.status == "dead"
      assert updated.attempt_count == 5

      assert_receive {:dead_letter, _delivery}, 1000
    after
      Application.delete_env(:observatory, :webhook_delivery_fn)
    end
  end
end
