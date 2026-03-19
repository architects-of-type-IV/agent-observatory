defmodule IchorWeb.DashboardGatewayHandlers do
  @moduledoc """
  Gateway-related dashboard hooks kept only for the current visible UI surface.
  """

  @doc "Subscribe to gateway PubSub topics. Kept as a no-op compatibility hook."
  def subscribe_gateway_topics, do: :ok

  @doc "Seed gateway assigns used by the visible dashboard pages."
  def seed_gateway_assigns(socket), do: socket

  @doc "Gateway signal dispatch for the visible dashboard pages."
  def handle_gateway_info(_msg, socket), do: socket
end
