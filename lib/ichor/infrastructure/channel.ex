defmodule Ichor.Infrastructure.Channel do
  @moduledoc """
  Behaviour for message delivery channel adapters.

  Each adapter implements a different transport mechanism (tmux, mailbox, webhook, ssh, etc.)
  and declares which key in `agent.channels` it serves via `channel_key/0`.

  Adapters are registered at runtime with the Router via `config :ichor, :channels`.
  """

  @doc "The key in `agent.channels` this adapter reads its address from (e.g., `:tmux`, `:mailbox`)."
  @callback channel_key() :: atom()

  @doc "Deliver a payload to the given address. Returns :ok or {:error, reason}."
  @callback deliver(address :: String.t(), payload :: map()) :: :ok | {:error, term()}

  @doc "Check whether the given address is currently reachable."
  @callback available?(address :: String.t()) :: boolean()

  @doc """
  Whether this channel should skip certain message types.
  Override to filter out system messages, heartbeats, etc.
  Defaults to false (deliver everything).
  """
  @callback skip?(payload :: map()) :: boolean()

  @optional_callbacks [skip?: 1]
end
