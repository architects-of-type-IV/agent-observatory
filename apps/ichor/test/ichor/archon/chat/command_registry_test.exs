defmodule Ichor.Archon.Chat.CommandRegistryTest do
  use ExUnit.Case, async: false

  alias Ichor.Archon.Chat.CommandRegistry

  setup do
    Application.put_env(
      :ichor,
      :archon_chat_action_runner_module,
      Ichor.TestSupport.ArchonStubActionRunner
    )

    Application.put_env(:ichor, :archon_test_pid, self())
    Application.put_env(:ichor, :archon_action_runner_result, {:ok, %{"status" => "ok"}})

    on_exit(fn ->
      Application.delete_env(:ichor, :archon_chat_action_runner_module)
      Application.delete_env(:ichor, :archon_test_pid)
      Application.delete_env(:ichor, :archon_action_runner_result)
    end)

    :ok
  end

  test "dispatches a simple observation command" do
    assert {:ok, %{type: :agents, data: %{"status" => "ok"}}} =
             CommandRegistry.dispatch(%{command: "/agents", remainder: nil})

    assert_receive {:archon_action, :agents, Ichor.Archon.Tools.Agents, :list_agents, %{}}
  end

  test "dispatches managerial summary commands" do
    assert {:ok, %{type: :manager_snapshot}} =
             CommandRegistry.dispatch(%{command: "/manager", remainder: nil})

    assert_receive {:archon_action, :manager_snapshot, Ichor.Archon.Tools.Manager,
                    :manager_snapshot, %{}}

    assert {:ok, %{type: :attention_queue}} =
             CommandRegistry.dispatch(%{command: "/attention", remainder: nil})

    assert_receive {:archon_action, :attention_queue, Ichor.Archon.Tools.Manager,
                    :attention_queue, %{}}
  end

  test "dispatches argument-bearing commands with parsed params" do
    assert {:ok, %{type: :agent_events}} =
             CommandRegistry.dispatch(%{command: "/events", remainder: "alpha 25"})

    assert_receive {:archon_action, :agent_events, Ichor.Archon.Tools.Events, :agent_events,
                    %{agent_id: "alpha", limit: 25}}
  end

  test "returns usage error for incomplete msg command" do
    assert {:ok, %{type: :error, data: "Usage: /msg <target> <message>"}} =
             CommandRegistry.dispatch(%{command: "/msg", remainder: nil})
  end

  test "returns unknown command help text" do
    assert {:ok, %{type: :error, data: data}} =
             CommandRegistry.dispatch(%{command: "/wat", remainder: nil})

    assert data =~ "Unknown command: /wat"
    assert data =~ "Observation:"
    assert data =~ "/agents /teams"
  end
end
