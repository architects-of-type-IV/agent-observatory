defmodule Ichor.Fleet.AgentProcess.Delivery do
  @moduledoc """
  Message normalization and backend delivery for agent processes.

  Handles two concerns:
  - Normalizing incoming messages into a canonical map shape
  - Dispatching messages to the configured backend transport (tmux, SSH, webhook)
  """

  alias Ichor.Gateway.Channels.{SshTmux, Tmux, WebhookAdapter}

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
    Tmux.deliver(session, %{content: content})
  end

  def deliver(%{type: :ssh_tmux, address: address}, msg) do
    content = msg[:content] || inspect(msg)
    SshTmux.deliver(address, %{content: content})
  end

  def deliver(%{type: :ssh_tmux, session: session, host: host}, msg) do
    content = msg[:content] || inspect(msg)
    SshTmux.deliver("#{session}@#{host}", %{content: content})
  end

  def deliver(%{type: :webhook, url: url}, msg) do
    WebhookAdapter.deliver(url, msg)
  end

  def deliver(%{type: _type}, _msg), do: :ok

  # ── PubSub ───────────────────────────────────────────────────────────

  @doc "Broadcast a message delivery event to the messages stream."
  @spec broadcast(String.t(), map()) :: :ok
  def broadcast(agent_id, msg) do
    Ichor.Signals.emit(:message_delivered, %{agent_id: agent_id, msg_map: msg})
  end
end
