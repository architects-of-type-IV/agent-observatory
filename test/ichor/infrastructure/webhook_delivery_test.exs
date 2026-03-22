defmodule Ichor.Infrastructure.WebhookDeliveryTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Ichor.Infrastructure.WebhookDelivery

  setup do
    Sandbox.checkout(Ichor.Repo)
  end

  describe "enqueue/4" do
    test "creates a delivery record with status :pending" do
      {:ok, delivery} =
        WebhookDelivery.enqueue("http://example.com", "payload", "sig123", "agent-1")

      assert delivery.target_url == "http://example.com"
      assert delivery.payload == "payload"
      assert delivery.signature == "sig123"
      assert delivery.agent_id == "agent-1"
      assert delivery.status == :pending
      assert delivery.attempt_count == 0
      assert %DateTime{} = delivery.next_retry_at
    end

    test "assigns a uuid id" do
      {:ok, delivery} = WebhookDelivery.enqueue("http://example.com", "body", "sig", "agent-2")
      assert is_binary(delivery.id)
      assert String.length(delivery.id) > 0
    end
  end

  describe "get/1" do
    test "retrieves an existing delivery by id" do
      {:ok, created} = WebhookDelivery.enqueue("http://example.com", "data", "sig", "agent-1")
      {:ok, found} = WebhookDelivery.get(created.id)

      assert found.id == created.id
      assert found.target_url == "http://example.com"
    end

    test "returns error for unknown id" do
      result = WebhookDelivery.get("00000000-0000-0000-0000-000000000000")
      assert {:error, _} = result
    end
  end

  describe "mark_delivered/1" do
    test "sets status to :delivered" do
      {:ok, delivery} = WebhookDelivery.enqueue("http://example.com", "payload", "sig", "agent-1")
      {:ok, delivered} = WebhookDelivery.mark_delivered(delivery)

      assert delivered.status == :delivered
    end
  end

  describe "schedule_retry/1" do
    test "sets status to :failed and updates retry fields" do
      {:ok, delivery} = WebhookDelivery.enqueue("http://example.com", "payload", "sig", "agent-1")
      next_retry = DateTime.utc_now() |> DateTime.add(60, :second) |> DateTime.truncate(:second)

      {:ok, retried} =
        WebhookDelivery.schedule_retry(
          delivery,
          %{next_retry_at: next_retry, attempt_count: 1}
        )

      assert retried.status == :failed
      assert retried.attempt_count == 1
    end
  end

  describe "mark_dead/1" do
    test "sets status to :dead" do
      {:ok, delivery} = WebhookDelivery.enqueue("http://example.com", "payload", "sig", "agent-1")
      {:ok, dead} = WebhookDelivery.mark_dead(delivery, %{attempt_count: 5})

      assert dead.status == :dead
      assert dead.attempt_count == 5
    end
  end

  describe "dead_letters_for_agent/1" do
    test "returns only dead deliveries for the given agent" do
      {:ok, d1} = WebhookDelivery.enqueue("http://fail.com", "p", "s", "agent-dead")
      {:ok, _} = WebhookDelivery.mark_dead(d1, %{attempt_count: 3})

      {:ok, d2} = WebhookDelivery.enqueue("http://ok.com", "p", "s", "agent-dead")
      {:ok, _} = WebhookDelivery.mark_delivered(d2)

      {:ok, dead_letters} = WebhookDelivery.dead_letters_for_agent("agent-dead")

      assert length(dead_letters) == 1
      assert hd(dead_letters).status == :dead
    end

    test "returns empty list when agent has no dead letters" do
      {:ok, letters} = WebhookDelivery.dead_letters_for_agent("agent-no-dead")
      assert letters == []
    end
  end

  describe "all_dead_letters/0" do
    test "returns all dead deliveries across agents" do
      {:ok, d1} = WebhookDelivery.enqueue("http://a.com", "p", "s", "agent-x")
      {:ok, _} = WebhookDelivery.mark_dead(d1, %{attempt_count: 3})

      {:ok, d2} = WebhookDelivery.enqueue("http://b.com", "p", "s", "agent-y")
      {:ok, _} = WebhookDelivery.mark_dead(d2, %{attempt_count: 3})

      {:ok, all_dead} = WebhookDelivery.all_dead_letters()

      ids = Enum.map(all_dead, & &1.id)
      assert d1.id in ids
      assert d2.id in ids
    end
  end

  describe "due_for_delivery/0" do
    test "returns pending deliveries with next_retry_at in the past or present" do
      {:ok, delivery} = WebhookDelivery.enqueue("http://example.com", "payload", "sig", "agent-1")
      # Force next_retry_at to be clearly in the past by updating directly via schedule_retry
      past = DateTime.utc_now() |> DateTime.add(-10, :second) |> DateTime.truncate(:second)

      {:ok, _} =
        WebhookDelivery.schedule_retry(delivery, %{next_retry_at: past, attempt_count: 1})

      # schedule_retry sets status :failed, which is also included in due_for_delivery
      {:ok, due} = WebhookDelivery.due_for_delivery()

      ids = Enum.map(due, & &1.id)
      assert delivery.id in ids
    end

    test "does not return delivered or dead deliveries" do
      {:ok, d1} = WebhookDelivery.enqueue("http://done.com", "p", "s", "agent-1")
      {:ok, _} = WebhookDelivery.mark_delivered(d1)

      {:ok, d2} = WebhookDelivery.enqueue("http://dead.com", "p", "s", "agent-1")
      {:ok, _} = WebhookDelivery.mark_dead(d2, %{attempt_count: 5})

      {:ok, due} = WebhookDelivery.due_for_delivery()
      ids = Enum.map(due, & &1.id)

      refute d1.id in ids
      refute d2.id in ids
    end
  end

  describe "full lifecycle: enqueue -> get -> mark_delivered" do
    test "end-to-end happy path" do
      {:ok, delivery} = WebhookDelivery.enqueue("http://example.com", "payload", "sig", "agent-1")
      assert delivery.status == :pending

      {:ok, found} = WebhookDelivery.get(delivery.id)
      assert found.id == delivery.id

      {:ok, delivered} = WebhookDelivery.mark_delivered(delivery)
      assert delivered.status == :delivered
    end
  end

  describe "dead letter lifecycle" do
    test "enqueue -> mark_dead -> dead_letters_for_agent" do
      {:ok, delivery} = WebhookDelivery.enqueue("http://fail.com", "payload", "sig", "agent-1")
      {:ok, dead} = WebhookDelivery.mark_dead(delivery, %{attempt_count: 5})
      assert dead.status == :dead

      {:ok, dead_letters} = WebhookDelivery.dead_letters_for_agent("agent-1")
      assert dead_letters != []
      assert Enum.any?(dead_letters, &(&1.id == dead.id))
    end
  end
end
