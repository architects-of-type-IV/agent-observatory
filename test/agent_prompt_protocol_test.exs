defmodule AgentPromptProtocolTest do
  use ExUnit.Case, async: false

  doctest AgentPromptProtocol

  setup do
    on_exit(fn ->
      for key <- [
            :send_function,
            :inbox_function,
            :operator_id,
            :operator_description,
            :operator_capabilities
          ] do
        Application.delete_env(:agent_prompt_protocol, key)
      end
    end)

    agents = [
      %{id: 1, name: "coordinator", capability: "coordinator"},
      %{id: 2, name: "lead", capability: "lead"},
      %{id: 3, name: "builder", capability: "builder"},
      %{id: 4, name: "scout", capability: "scout"}
    ]

    {:ok, agents: agents}
  end

  describe "critical_rules/1" do
    test "names both tools" do
      rules = AgentPromptProtocol.critical_rules()

      assert rules =~ "send_message"
      assert rules =~ "check_inbox"
    end

    test "applies the tool prefix" do
      rules = AgentPromptProtocol.critical_rules("mcp__team__")

      assert rules =~ "mcp__team__send_message"
      assert rules =~ "mcp__team__check_inbox"
    end

    test "defaults to no prefix" do
      assert AgentPromptProtocol.critical_rules() == AgentPromptProtocol.critical_rules("")
    end

    test "names the configured tools instead" do
      Application.put_env(:agent_prompt_protocol, :send_function, "post")
      Application.put_env(:agent_prompt_protocol, :inbox_function, "poll")

      rules = AgentPromptProtocol.critical_rules()

      assert rules =~ "post"
      assert rules =~ "poll"
      refute rules =~ "send_message"
    end

    test "calls out the narrate-instead-of-call failure mode" do
      assert AgentPromptProtocol.critical_rules() =~ ~s(I would send)
    end

    test "has no trailing newline" do
      refute String.ends_with?(AgentPromptProtocol.critical_rules(), "\n")
    end
  end

  describe "roster_block/2" do
    test "qualifies each name with the session" do
      roster = AgentPromptProtocol.roster_block("run-7", ["lead", "builder"])

      assert roster =~ "- lead: run-7-lead"
      assert roster =~ "- builder: run-7-builder"
    end

    test "always includes the operator" do
      assert AgentPromptProtocol.roster_block("run-7", ["lead"]) =~ "- operator: operator"
    end

    test "an empty roster still lists the operator" do
      assert AgentPromptProtocol.roster_block("run-7", []) =~ "operator"
    end

    test "honours a configured operator id" do
      Application.put_env(:agent_prompt_protocol, :operator_id, "human")

      assert AgentPromptProtocol.roster_block("run-7", ["lead"]) =~ "- human: human"
    end
  end

  describe "roster_from_entries/1" do
    test "uses the ids given rather than deriving them" do
      roster = AgentPromptProtocol.roster_from_entries([{"lead", "custom-id-1"}])

      assert roster =~ "- lead: custom-id-1"
    end

    test "names the tools the ids are for" do
      assert AgentPromptProtocol.roster_from_entries([]) =~ "send_message/check_inbox"
    end
  end

  describe "announce_ready/1" do
    test "tells the agent to message itself" do
      block = AgentPromptProtocol.announce_ready("run-7-coordinator")

      assert block =~ ~s(from: "run-7-coordinator")
      assert block =~ ~s(to: "run-7-coordinator")
      assert block =~ "COORDINATOR READY"
    end

    test "explains that nothing goes upstream" do
      assert AgentPromptProtocol.announce_ready("x") =~ "No READY message needs to go upstream"
    end
  end

  describe "allowed_contacts/5 with allow rules" do
    test "lists a direct contact's own session id", %{agents: agents} do
      rules = [%{from: 1, to: 2, policy: "allow"}]

      block = AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7")

      assert block =~ ~s("run-7-lead" -- lead)
    end

    test "lists several direct contacts", %{agents: agents} do
      rules = [
        %{from: 1, to: 2, policy: "allow"},
        %{from: 1, to: 3, policy: "allow"}
      ]

      block = AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7")

      assert block =~ "run-7-lead"
      assert block =~ "run-7-builder"
    end

    test "ignores rules originating from other slots", %{agents: agents} do
      rules = [%{from: 2, to: 3, policy: "allow"}]

      block = AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7")

      refute block =~ ~s("run-7-builder" -- builder)
    end

    test "denies everyone not reachable", %{agents: agents} do
      rules = [%{from: 1, to: 2, policy: "allow"}]

      block = AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7")

      assert block =~ "Do NOT message"
      assert block =~ "builder"
      assert block =~ "scout"
    end

    test "never denies the agent itself", %{agents: agents} do
      block = AgentPromptProtocol.allowed_contacts(1, [], agents, "run-7")

      [_, deny] = String.split(block, "Do NOT message")
      refute deny =~ "coordinator"
    end

    test "omits the deny line when everyone is reachable" do
      agents = [%{id: 1, name: "a"}, %{id: 2, name: "b"}]
      rules = [%{from: 1, to: 2, policy: "allow"}]

      block = AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7")

      refute block =~ "Do NOT message"
    end

    test "says so explicitly when an agent is isolated", %{agents: agents} do
      block = AgentPromptProtocol.allowed_contacts(1, [], agents, "run-7")

      assert block =~ "none -- you are isolated"
    end
  end

  describe "allowed_contacts/5 with route rules" do
    test "lists the relay's id, not the target's", %{agents: agents} do
      rules = [%{from: 3, to: 1, policy: "route", via: 2}]

      block = AgentPromptProtocol.allowed_contacts(3, rules, agents, "run-7")

      assert block =~ ~s|"run-7-lead" -- coordinator (routed via lead)|
      refute block =~ ~s("run-7-coordinator")
    end

    test "still denies the routed target directly", %{agents: agents} do
      rules = [%{from: 3, to: 1, policy: "route", via: 2}]

      block = AgentPromptProtocol.allowed_contacts(3, rules, agents, "run-7")

      assert block =~ "Do NOT message"
      assert block =~ "coordinator"
    end

    test "a route rule with no :via key does not crash", %{agents: agents} do
      rules = [%{from: 3, to: 1, policy: "route"}]

      block = AgentPromptProtocol.allowed_contacts(3, rules, agents, "run-7")

      assert block =~ "unknown"
    end

    test "a route rule with a nil :via does not crash", %{agents: agents} do
      rules = [%{from: 3, to: 1, policy: "route", via: nil}]

      assert AgentPromptProtocol.allowed_contacts(3, rules, agents, "run-7") =~ "unknown"
    end
  end

  describe "allowed_contacts/5 edge cases" do
    test "a rule naming a slot that no longer exists is visible, not fatal", %{agents: agents} do
      rules = [%{from: 1, to: 99, policy: "allow"}]

      block = AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7")

      assert block =~ "unknown-99"
    end

    test "an unknown policy is ignored", %{agents: agents} do
      rules = [%{from: 1, to: 2, policy: "maybe"}]

      block = AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7")

      refute block =~ "run-7-lead"
    end

    test "extra contacts are appended", %{agents: agents} do
      rules = [%{from: 1, to: 2, policy: "allow"}]
      extra = [{"operator", "final deliverables"}]

      block = AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7", extra)

      assert block =~ ~s("operator" -- final deliverables)
      assert block =~ "run-7-lead"
    end

    test "names the configured send tool" do
      Application.put_env(:agent_prompt_protocol, :send_function, "post")

      assert AgentPromptProtocol.allowed_contacts(1, [], [], "run-7") =~ "post"
    end
  end

  describe "extra_contacts_for/1" do
    test "gives a coordinator the operator" do
      assert AgentPromptProtocol.extra_contacts_for(%{capability: "coordinator"}) ==
               [{"operator", "final deliverables to the dashboard"}]
    end

    test "gives other capabilities nothing" do
      for capability <- ["builder", "scout", "lead"] do
        assert AgentPromptProtocol.extra_contacts_for(%{capability: capability}) == []
      end
    end

    test "handles a map with no capability" do
      assert AgentPromptProtocol.extra_contacts_for(%{}) == []
      assert AgentPromptProtocol.extra_contacts_for(%{name: "x"}) == []
    end

    test "honours configured operator capabilities" do
      Application.put_env(:agent_prompt_protocol, :operator_capabilities, ["lead"])

      assert [{"operator", _}] = AgentPromptProtocol.extra_contacts_for(%{capability: "lead"})
      assert AgentPromptProtocol.extra_contacts_for(%{capability: "coordinator"}) == []
    end

    test "honours a configured operator id and description" do
      Application.put_env(:agent_prompt_protocol, :operator_id, "human")
      Application.put_env(:agent_prompt_protocol, :operator_description, "the boss")

      assert AgentPromptProtocol.extra_contacts_for(%{capability: "coordinator"}) ==
               [{"human", "the boss"}]
    end
  end

  describe "render_template/3" do
    test "delegates to Template" do
      assert AgentPromptProtocol.render_template("{{a}}", %{"a" => "1"}) == "1"
    end
  end

  describe "assembling a full prompt" do
    test "the roster ids match the allowed-contact ids", %{agents: agents} do
      # The bug this library exists to prevent: a roster that lists ids the
      # contacts block does not agree with.
      rules = [%{from: 1, to: 2, policy: "allow"}]
      session = "run-7"

      roster = AgentPromptProtocol.roster_block(session, Enum.map(agents, & &1.name))
      contacts = AgentPromptProtocol.allowed_contacts(1, rules, agents, session)

      assert roster =~ "run-7-lead"
      assert contacts =~ "run-7-lead"
    end
  end
end
