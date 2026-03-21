defmodule Ichor.Infrastructure.AgentState do
  @moduledoc """
  Pure state-transition helpers for `AgentProcess`.

  Every function here takes an `AgentProcess` struct and returns a new one.
  None of them perform IO, emit signals, or touch the registry.  This makes
  them trivially testable and composable.

  ## Fields
  - `message_log`  — bounded history of all received messages (newest first).
  - `inbox`        — user-facing unread messages; returned and cleared by
                     `get_unread/1`.  Alias: the old `unread` field was
                     split so delivery-buffering is handled separately.
  - `pending_delivery` — messages buffered while the agent is paused and
                         drained to the backend on resume.
  """

  alias Ichor.Infrastructure.AgentMessage

  @max_message_log 200

  @doc """
  Record an incoming normalized message into the log and inbox, routing
  delivery buffering based on current status.

  Returns `{normalized_message, new_state}` so the caller has direct access
  to the normalized message without inspecting internal state fields.

  - When `:active`, the message is ready for immediate delivery.
  - When not `:active`, the message is additionally appended to
    `pending_delivery` for deferred dispatch on resume.
  """
  @spec record_message(map(), map() | String.t()) :: {map(), map()}
  def record_message(%{id: agent_id} = state, raw_message) do
    msg = AgentMessage.normalize(raw_message, agent_id)

    new_state =
      state
      |> prepend_to_log(msg)
      |> prepend_to_inbox(msg)
      |> maybe_buffer(msg)

    {msg, new_state}
  end

  @doc """
  Drain the `pending_delivery` buffer (returning it in arrival order) and
  transition the agent to `:active` status.

  The caller is responsible for actually delivering the drained messages via
  `AgentDelivery.deliver_many/2`.
  """
  @spec drain_pending(map()) :: {[map()], map()}
  def drain_pending(state) do
    messages = Enum.reverse(state.pending_delivery)
    new_state = %{state | status: :active, pending_delivery: []}
    {messages, new_state}
  end

  @doc """
  Return the current inbox (newest first → oldest last) and clear it.
  """
  @spec pop_inbox(map()) :: {[map()], map()}
  def pop_inbox(state) do
    {Enum.reverse(state.inbox), %{state | inbox: []}}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp prepend_to_log(state, msg) do
    %{state | message_log: Enum.take([msg | state.message_log], @max_message_log)}
  end

  defp prepend_to_inbox(state, msg) do
    %{state | inbox: [msg | state.inbox]}
  end

  defp maybe_buffer(%{status: :active} = state, _msg), do: state

  defp maybe_buffer(state, msg) do
    %{state | pending_delivery: [msg | state.pending_delivery]}
  end
end
