defmodule Ichor.TestSupport.GatewayStubWebhookChannel do
  @moduledoc false

  def channel_key, do: :webhook
  def available?(address), do: is_binary(address) and address != ""

  def deliver(address, payload) do
    if pid = Application.get_env(:ichor, :gateway_test_pid) do
      send(pid, {:gateway_webhook_delivery, address, payload})
    end

    :ok
  end
end
