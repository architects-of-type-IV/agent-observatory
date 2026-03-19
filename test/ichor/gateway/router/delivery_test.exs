defmodule Ichor.Gateway.Router.DeliveryTest do
  use ExUnit.Case, async: true

  alias Ichor.Gateway.Envelope
  alias Ichor.Gateway.Router.Delivery

  setup do
    Application.put_env(:ichor, :gateway_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:ichor, :gateway_test_pid)
    end)

    :ok
  end

  test "counts only primary deliveries and adds agent_id for webhook payloads" do
    envelope = Envelope.new("agent:alpha", %{content: "hello"})

    recipients = [
      %{
        id: "alpha",
        session_id: "alpha-session",
        channels: %{mailbox: "alpha-box", webhook: "https://example.test/hook"}
      }
    ]

    channels = [
      {Ichor.TestSupport.GatewayStubMailboxChannel, primary: true},
      {Ichor.TestSupport.GatewayStubWebhookChannel, primary: false}
    ]

    assert 1 = Delivery.deliver(envelope, recipients, channels)

    assert_receive {:gateway_webhook_delivery, "https://example.test/hook", payload}
    assert payload[:agent_id] == "alpha-session"
    assert payload[:content] == "hello"
  end
end
