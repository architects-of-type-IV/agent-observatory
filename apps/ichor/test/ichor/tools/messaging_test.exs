defmodule Ichor.Tools.MessagingTest do
  use ExUnit.Case, async: true

  setup do
    Application.put_env(:ichor, :tools_test_pid, self())

    Application.put_env(
      :ichor,
      :tools_messaging_comms_module,
      Ichor.TestSupport.ToolsStubOperator
    )

    Application.put_env(
      :ichor,
      :tools_messaging_fleet_agent_module,
      Ichor.TestSupport.ToolsStubFleetAgent
    )

    Application.put_env(:ichor, :tools_messaging_router_module, Ichor.TestSupport.ToolsStubRouter)

    on_exit(fn ->
      Application.delete_env(:ichor, :tools_test_pid)
      Application.delete_env(:ichor, :tools_messaging_comms_module)
      Application.delete_env(:ichor, :tools_messaging_fleet_agent_module)
      Application.delete_env(:ichor, :tools_messaging_router_module)
      Application.delete_env(:ichor, :tools_operator_delivered)
      Application.delete_env(:ichor, :tools_fleet_agent_result)
      Application.delete_env(:ichor, :tools_router_result)
    end)

    :ok
  end

  test "send_as_operator delegates through operator and preserves result shape" do
    Application.put_env(:ichor, :tools_operator_delivered, 2)

    assert {:ok, %{status: "sent", to: "operator", delivered: delivered}} =
             Ichor.Tools.Messaging.send_as_operator("operator", "status")

    assert delivered == 2
    assert_received {:tools_operator_send, "operator", "status"}
  end

  test "send_as_agent routes grouped targets through router" do
    Application.put_env(:ichor, :tools_router_result, {:ok, 3})

    assert {:ok, %{status: "sent", to: "team:alpha", delivered: 3}} =
             Ichor.Tools.Messaging.send_as_agent("agent-1", "team:alpha", "status")

    assert_received {:tools_router_broadcast, "team:alpha", %{content: "status", from: "agent-1"}}
  end

  test "send_as_agent tries direct agent send for plain agent target" do
    Application.put_env(:ichor, :tools_fleet_agent_result, {:ok, %{}})

    assert {:ok, %{status: "sent", to: "agent-2", delivered: 1, via: "fleet"}} =
             Ichor.Tools.Messaging.send_as_agent("agent-1", "agent-2", "ping")

    assert_received {:tools_fleet_agent_send, "agent-2", "ping", %{from: "agent-1"}}
  end
end
