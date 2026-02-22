defmodule Observatory.Gateway.WebhookDeliveryTest do
  use Observatory.DataCase

  alias Observatory.Gateway.WebhookDelivery

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{target_url: "https://example.com/hook", payload: "{}", agent_id: "agent-1"}
      changeset = WebhookDelivery.changeset(%WebhookDelivery{}, attrs)
      assert changeset.valid?
    end

    test "invalid without target_url" do
      attrs = %{payload: "{}", agent_id: "agent-1"}
      changeset = WebhookDelivery.changeset(%WebhookDelivery{}, attrs)
      refute changeset.valid?
      assert %{target_url: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without payload" do
      attrs = %{target_url: "https://example.com/hook", agent_id: "agent-1"}
      changeset = WebhookDelivery.changeset(%WebhookDelivery{}, attrs)
      refute changeset.valid?
      assert %{payload: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without agent_id" do
      attrs = %{target_url: "https://example.com/hook", payload: "{}"}
      changeset = WebhookDelivery.changeset(%WebhookDelivery{}, attrs)
      refute changeset.valid?
      assert %{agent_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "defaults status to pending" do
      attrs = %{target_url: "https://example.com/hook", payload: "{}", agent_id: "agent-1"}
      changeset = WebhookDelivery.changeset(%WebhookDelivery{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :status) == "pending"
    end

    test "defaults attempt_count to 0" do
      attrs = %{target_url: "https://example.com/hook", payload: "{}", agent_id: "agent-1"}
      changeset = WebhookDelivery.changeset(%WebhookDelivery{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :attempt_count) == 0
    end

    test "rejects invalid status" do
      attrs = %{
        target_url: "https://example.com/hook",
        payload: "{}",
        agent_id: "agent-1",
        status: "bogus"
      }

      changeset = WebhookDelivery.changeset(%WebhookDelivery{}, attrs)
      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts all valid statuses" do
      for status <- ~w(pending delivered failed dead) do
        attrs = %{
          target_url: "https://example.com/hook",
          payload: "{}",
          agent_id: "agent-1",
          status: status
        }

        changeset = WebhookDelivery.changeset(%WebhookDelivery{}, attrs)
        assert changeset.valid?, "expected status #{status} to be valid"
      end
    end

    test "accepts optional fields" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        target_url: "https://example.com/hook",
        payload: "{}",
        agent_id: "agent-1",
        signature: "sha256=abc123",
        webhook_id: "wh-1",
        next_retry_at: now,
        inserted_at: now
      }

      changeset = WebhookDelivery.changeset(%WebhookDelivery{}, attrs)
      assert changeset.valid?
    end
  end
end
