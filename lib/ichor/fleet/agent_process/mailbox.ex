defmodule Ichor.Fleet.AgentProcess.Mailbox do
  @moduledoc """
  Mailbox routing and delivery helpers for agent processes.
  """

  alias Ichor.Fleet.AgentProcess.Delivery

  @max_message_buffer 200

  @doc "Normalize, buffer, broadcast, and route an incoming message. Returns updated state."
  @spec apply_incoming_message(Ichor.Fleet.AgentProcess.t(), map() | String.t()) ::
          Ichor.Fleet.AgentProcess.t()
  def apply_incoming_message(state, message) do
    normalized = Delivery.normalize(message, state.id)
    messages = Enum.take([normalized | state.messages], @max_message_buffer)
    Delivery.broadcast(state.id, normalized)
    route_message(normalized, %{state | messages: messages})
  end

  @doc "Flush all buffered unread messages to the backend and mark the agent active."
  @spec deliver_unread(Ichor.Fleet.AgentProcess.t()) :: Ichor.Fleet.AgentProcess.t()
  def deliver_unread(state) do
    state.unread |> Enum.reverse() |> Enum.each(&Delivery.deliver(state.backend, &1))
    %{state | status: :active}
  end

  @doc false
  @spec route_message(map(), Ichor.Fleet.AgentProcess.t()) :: Ichor.Fleet.AgentProcess.t()
  def route_message(message, %{status: status} = state) when status != :active do
    %{state | unread: [message | state.unread]}
  end

  def route_message(message, state) do
    if state.backend, do: Delivery.deliver(state.backend, message)
    %{state | unread: [message | state.unread]}
  end
end
