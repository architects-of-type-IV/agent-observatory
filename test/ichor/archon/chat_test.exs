defmodule Ichor.Archon.ChatTest do
  use ExUnit.Case, async: false

  alias Ichor.Archon.Chat

  setup do
    Application.put_env(
      :ichor,
      :archon_chat_action_runner_module,
      Ichor.TestSupport.ArchonStubActionRunner
    )

    Application.put_env(
      :ichor,
      :archon_chat_chain_builder_module,
      Ichor.TestSupport.ArchonStubChainBuilder
    )

    Application.put_env(
      :ichor,
      :archon_chat_turn_runner_module,
      Ichor.TestSupport.ArchonStubTurnRunner
    )

    Application.put_env(:ichor, :archon_test_pid, self())
    Application.put_env(:ichor, :archon_action_runner_result, {:ok, [%{"id" => "alpha"}]})

    on_exit(fn ->
      Application.delete_env(:ichor, :archon_chat_action_runner_module)
      Application.delete_env(:ichor, :archon_chat_chain_builder_module)
      Application.delete_env(:ichor, :archon_chat_turn_runner_module)
      Application.delete_env(:ichor, :archon_test_pid)
      Application.delete_env(:ichor, :archon_action_runner_result)
    end)

    :ok
  end

  test "slash commands preserve history and return typed payloads" do
    history = [%{content: "existing"}]

    assert {:ok, %{type: :agents, data: [%{"id" => "alpha"}]}, ^history} =
             Chat.chat("/agents", history)
  end

  test "free text delegates through chain builder and turn runner" do
    history = [%{content: "before"}]

    assert {:ok, "stubbed response", [%{content: "before"}, "hello archon"]} =
             Chat.chat("hello archon", history)

    assert_receive {:archon_turn_runner, %{messages: [:system_seed], last_message: nil}, ^history,
                    "hello archon"}
  end
end
