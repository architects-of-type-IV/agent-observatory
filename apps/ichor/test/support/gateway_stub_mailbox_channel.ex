defmodule Ichor.TestSupport.GatewayStubMailboxChannel do
  @moduledoc false

  def channel_key, do: :mailbox
  def available?(address), do: is_binary(address) and address != ""
  def deliver(_address, _payload), do: :ok
end
