defmodule Observatory.Gateway.Channel do
  @moduledoc """
  Behaviour for message delivery channel adapters.
  Each adapter implements a different transport mechanism (tmux, mailbox, webhook).
  """

  @doc "Deliver a payload to the given address. Returns :ok or {:error, reason}."
  @callback deliver(address :: String.t(), payload :: map()) :: :ok | {:error, term()}

  @doc "Check whether the given address is currently reachable."
  @callback available?(address :: String.t()) :: boolean()
end
