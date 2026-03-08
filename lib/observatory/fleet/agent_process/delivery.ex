defmodule Observatory.Fleet.AgentProcess.Delivery do
  @moduledoc """
  Message normalization and backend delivery for agent processes.

  Handles two concerns:
  - Normalizing incoming messages into a canonical map shape
  - Dispatching messages to the configured backend transport (tmux, SSH, webhook)
  """

  require Logger

  # ── Message Normalization ────────────────────────────────────────────

  @doc "Normalize a message into canonical form with ID, recipient, and timestamp."
  @spec normalize(map(), String.t()) :: map()
  def normalize(msg, to) when is_map(msg) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        to: to,
        timestamp: DateTime.utc_now()
      },
      msg
    )
  end

  @spec normalize(String.t(), String.t()) :: map()
  def normalize(content, to) when is_binary(content) do
    %{
      id: Ecto.UUID.generate(),
      to: to,
      from: "system",
      content: content,
      type: :message,
      timestamp: DateTime.utc_now()
    }
  end

  # ── Backend Delivery ─────────────────────────────────────────────────

  @doc "Deliver a message to the agent's configured backend transport."
  @spec deliver(map() | nil, map()) :: :ok
  def deliver(nil, _msg), do: :ok

  def deliver(%{type: :tmux, session: session}, msg) do
    content = msg[:content] || inspect(msg)
    Observatory.Gateway.Channels.Tmux.deliver(session, %{content: content})
  end

  def deliver(%{type: :ssh_tmux} = backend, msg) do
    address = "#{backend.session}@#{backend.host}"
    content = msg[:content] || inspect(msg)
    Observatory.Gateway.Channels.SshTmux.deliver(address, %{content: content})
  end

  def deliver(%{type: :webhook, url: url}, msg) do
    Observatory.Gateway.Channels.WebhookAdapter.deliver(url, msg)
  end

  def deliver(%{type: type}, _msg) do
    Logger.warning("[AgentProcess.Delivery] Unknown backend type: #{type}")
    :ok
  end

  # ── PubSub ───────────────────────────────────────────────────────────

  @doc "Broadcast a message delivery event to the messages stream."
  @spec broadcast(String.t(), map()) :: :ok
  def broadcast(agent_id, msg) do
    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "messages:stream",
      {:message_delivered, agent_id, msg}
    )
  end
end
