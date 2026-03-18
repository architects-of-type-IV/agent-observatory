defmodule Ichor.Fleet.AgentProcess.MailboxTest do
  use ExUnit.Case, async: true

  alias Ichor.Fleet.AgentProcess.Mailbox

  test "buffers unread messages when agent is paused" do
    state = %{id: "agent-1", status: :paused, unread: [], messages: [], backend: nil}
    updated = Mailbox.apply_incoming_message(state, "hello")

    assert length(updated.messages) == 1
    assert length(updated.unread) == 1
    assert hd(updated.unread).content == "hello"
  end
end
