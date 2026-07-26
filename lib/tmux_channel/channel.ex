defmodule TmuxChannel.Channel do
  @moduledoc """
  Behaviour for message delivery channel adapters.

  Each adapter implements a different transport (tmux, mailbox, webhook, ssh)
  and declares which address key it serves via `c:channel_key/0`. `TmuxChannel`
  itself implements this behaviour with `channel_key/0` returning `:tmux`.

  Implementing this behaviour lets a host application route a message to
  whichever adapter matches an address key, without knowing the transport.
  """

  @doc "The address key this adapter reads its target from (e.g. `:tmux`, `:mailbox`)."
  @callback channel_key() :: atom()

  @doc "Deliver a payload to the given address. Returns `:ok` or `{:error, reason}`."
  @callback deliver(address :: String.t(), payload :: map()) :: :ok | {:error, term()}

  @doc "Whether the given address is currently reachable."
  @callback available?(address :: String.t()) :: boolean()

  @doc """
  Whether this channel should skip a payload.

  Override to filter out system messages, heartbeats, and the like. Defaults to
  delivering everything.
  """
  @callback skip?(payload :: map()) :: boolean()

  @optional_callbacks [skip?: 1]
end
