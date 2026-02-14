defmodule Observatory.Mailbox do
  @moduledoc """
  Per-agent mailbox for storing and managing messages.
  Uses ETS for lightweight, in-memory message storage.
  """
  use GenServer
  require Logger

  @table_name :observatory_mailboxes

  # ═══════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Send a message to a specific agent.
  """
  def send_message(to, from, content, opts \\ []) do
    GenServer.call(__MODULE__, {:send_message, to, from, content, opts})
  end

  @doc """
  Get all messages for an agent.
  """
  def get_messages(agent_id) do
    GenServer.call(__MODULE__, {:get_messages, agent_id})
  end

  @doc """
  Mark a message as read.
  """
  def mark_read(agent_id, message_id) do
    GenServer.call(__MODULE__, {:mark_read, agent_id, message_id})
  end

  @doc """
  Get unread message count for an agent.
  """
  def unread_count(agent_id) do
    GenServer.call(__MODULE__, {:unread_count, agent_id})
  end

  @doc """
  Clear all messages for an agent.
  """
  def clear_messages(agent_id) do
    GenServer.call(__MODULE__, {:clear_messages, agent_id})
  end

  # ═══════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    # Create ETS table: {agent_id, [messages]}
    :ets.new(@table_name, [:named_table, :public, :set])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:send_message, to, from, content, opts}, _from, state) do
    message = %{
      id: generate_id(),
      from: from,
      to: to,
      content: content,
      type: Keyword.get(opts, :type, :text),
      timestamp: DateTime.utc_now(),
      read: false,
      metadata: Keyword.get(opts, :metadata, %{})
    }

    # Append message to agent's mailbox
    messages = get_agent_messages(to)
    updated_messages = [message | messages]
    :ets.insert(@table_name, {to, updated_messages})

    # Broadcast new message event
    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "agent:#{to}",
      {:new_mailbox_message, message}
    )

    {:reply, {:ok, message}, state}
  end

  def handle_call({:get_messages, agent_id}, _from, state) do
    messages = get_agent_messages(agent_id)
    {:reply, messages, state}
  end

  def handle_call({:mark_read, agent_id, message_id}, _from, state) do
    messages = get_agent_messages(agent_id)

    updated_messages =
      Enum.map(messages, fn msg ->
        if msg.id == message_id do
          Map.put(msg, :read, true)
        else
          msg
        end
      end)

    :ets.insert(@table_name, {agent_id, updated_messages})
    {:reply, :ok, state}
  end

  def handle_call({:unread_count, agent_id}, _from, state) do
    count =
      agent_id
      |> get_agent_messages()
      |> Enum.count(fn msg -> !msg.read end)

    {:reply, count, state}
  end

  def handle_call({:clear_messages, agent_id}, _from, state) do
    :ets.delete(@table_name, agent_id)
    {:reply, :ok, state}
  end

  # ═══════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════

  defp get_agent_messages(agent_id) do
    case :ets.lookup(@table_name, agent_id) do
      [{^agent_id, messages}] -> messages
      [] -> []
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
