defmodule Ichor.Fleet.AgentDelivery do
  @moduledoc """
  Routes normalized messages to the appropriate backend transport.

  Supported backends:
  - `%{type: :tmux, session: session_name}` — local tmux paste-buffer delivery
  - `%{type: :ssh_tmux, address: address}` — SSH + tmux delivery (address format)
  - `%{type: :ssh_tmux, session: session, host: host}` — SSH + tmux (split fields)
  - `%{type: :webhook, url: url}` — HTTP webhook delivery
  - `nil` or unrecognised backend — no-op

  All functions are side-effect wrappers; they do not mutate process state.
  """

  alias Ichor.Fleet.AgentMessage
  alias Ichor.Infrastructure.Tmux
  alias Ichor.Infrastructure.WebhookAdapter

  @doc "Deliver a single message to the given backend. Returns `:ok` or `{:error, reason}`."
  @spec deliver(map() | nil, map()) :: :ok | {:error, term()}
  def deliver(nil, _msg), do: :ok

  def deliver(%{type: :tmux, session: session}, msg) when is_binary(session) do
    Tmux.deliver(session, %{content: AgentMessage.content(msg)})
  end

  def deliver(%{type: :webhook, url: url}, msg) do
    WebhookAdapter.deliver(url, msg)
  end

  def deliver(%{type: _type}, _msg), do: :ok

  @doc """
  Deliver a list of messages to the backend in arrival order.

  Used when draining the pending-delivery buffer on resume.
  """
  @spec deliver_many(map() | nil, [map()]) :: :ok
  def deliver_many(backend, messages) do
    Enum.each(messages, &deliver(backend, &1))
  end
end
