defmodule AgentPromptProtocolTest do
  use ExUnit.Case, async: false

  doctest AgentPromptProtocol

  setup do
    on_exit(fn ->
      for key <- [
            :send_function,
            :inbox_function,
            :tool_prefix,
            :session_separator,
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

      block =
        AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7", extra_contacts: extra)

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

  describe "session_id/2 and roster_entries/2" do
    test "session_id builds the shared convention" do
      assert AgentPromptProtocol.session_id("review-abc123", "lead") == "review-abc123-lead"
    end

    test "session_id honours a configured separator" do
      Application.put_env(:agent_prompt_protocol, :session_separator, ":")

      assert AgentPromptProtocol.session_id("run-7", "lead") == "run-7:lead"
    end

    test "roster_entries pairs each name with its id, in order" do
      assert AgentPromptProtocol.roster_entries("run-7", ["lead", "builder"]) ==
               [{"lead", "run-7-lead"}, {"builder", "run-7-builder"}]
    end

    test "roster_entries is empty for no names" do
      assert AgentPromptProtocol.roster_entries("run-7", []) == []
    end

    test "the ids in roster_entries are exactly the ids in the roster block" do
      names = ["lead", "builder"]
      block = AgentPromptProtocol.roster_block("run-7", names)

      for {_name, sid} <- AgentPromptProtocol.roster_entries("run-7", names) do
        assert block =~ sid
      end
    end

    test "the ids used for session creation match those in the contacts block", %{agents: agents} do
      # The property that matters: whatever creates endpoints from roster_entries
      # produces exactly the ids the prompt tells agents to address.
      rules = [%{from: 1, to: 2, policy: "allow"}]
      names = Enum.map(agents, & &1.name)

      entries = AgentPromptProtocol.roster_entries("run-7", names)
      block = AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7")

      {_, lead_sid} = Enum.find(entries, fn {name, _} -> name == "lead" end)
      assert block =~ lead_sid
    end

    test "a configured separator flows through every block", %{agents: agents} do
      Application.put_env(:agent_prompt_protocol, :session_separator, ":")

      assert AgentPromptProtocol.roster_block("run-7", ["lead"]) =~ "run-7:lead"

      assert AgentPromptProtocol.allowed_contacts(
               1,
               [%{from: 1, to: 2, policy: "allow"}],
               agents,
               "run-7"
             ) =~ "run-7:lead"
    end
  end

  describe "tool prefix consistency" do
    test "a configured prefix reaches every block", %{agents: agents} do
      Application.put_env(:agent_prompt_protocol, :tool_prefix, "mcp__ichor__")

      blocks = [
        AgentPromptProtocol.critical_rules(),
        AgentPromptProtocol.roster_block("run-7", ["lead"]),
        AgentPromptProtocol.allowed_contacts(1, [], agents, "run-7"),
        AgentPromptProtocol.announce_ready("run-7-lead")
      ]

      # Every mention of the tool must carry the prefix. A prompt whose blocks
      # disagree about the tool's name is the failure this library prevents.
      for block <- blocks do
        for [match] <- Regex.scan(~r/\S*send_message/, block) do
          assert match == "mcp__ichor__send_message", "unprefixed in: #{block}"
        end
      end
    end

    test "an explicit prefix overrides the configured one" do
      Application.put_env(:agent_prompt_protocol, :tool_prefix, "cfg__")

      assert AgentPromptProtocol.critical_rules("arg__") =~ "arg__send_message"
      refute AgentPromptProtocol.critical_rules("arg__") =~ "cfg__send_message"
    end

    test "roster_block takes a prefix" do
      assert AgentPromptProtocol.roster_block("run-7", ["lead"], "p__") =~ "p__send_message"
    end

    test "announce_ready takes a prefix" do
      assert AgentPromptProtocol.announce_ready("run-7-lead", "p__") =~ "p__send_message"
    end

    test "allowed_contacts takes a prefix", %{agents: agents} do
      block = AgentPromptProtocol.allowed_contacts(1, [], agents, "run-7", tool_prefix: "p__")

      assert block =~ "p__send_message"
    end
  end

  describe "allowed_contacts/5 with deny rules" do
    test "a deny rule grants nothing", %{agents: agents} do
      rules = [%{from: 1, to: 2, policy: "deny"}]

      block = AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7")

      refute block =~ ~s("run-7-lead")
    end

    test "a denied agent is named in the deny line", %{agents: agents} do
      rules = [%{from: 1, to: 2, policy: "deny"}]

      block = AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7")

      assert block =~ "Do NOT message"
      assert block =~ "lead"
    end

    test "deny overrides an allow between the same pair", %{agents: agents} do
      rules = [
        %{from: 1, to: 2, policy: "allow"},
        %{from: 1, to: 2, policy: "deny"}
      ]

      block = AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7")

      refute block =~ ~s("run-7-lead" -- lead)
    end

    test "deny overrides regardless of rule order", %{agents: agents} do
      rules = [
        %{from: 1, to: 2, policy: "deny"},
        %{from: 1, to: 2, policy: "allow"}
      ]

      block = AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7")

      refute block =~ ~s("run-7-lead" -- lead)
    end

    test "deny overrides a route to the same target", %{agents: agents} do
      rules = [
        %{from: 3, to: 1, policy: "route", via: 2},
        %{from: 3, to: 1, policy: "deny"}
      ]

      block = AgentPromptProtocol.allowed_contacts(3, rules, agents, "run-7")

      refute block =~ "routed via"
    end

    test "denying one target leaves others intact", %{agents: agents} do
      rules = [
        %{from: 1, to: 2, policy: "allow"},
        %{from: 1, to: 3, policy: "deny"}
      ]

      block = AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7")

      assert block =~ ~s("run-7-lead" -- lead)
      refute block =~ ~s("run-7-builder" -- builder)
    end

    test "the review-chain preset wiring renders correctly" do
      # lead(1), reviewer(2), builder(3), scout(4) -- the one preset that uses
      # the full policy vocabulary.
      agents = [
        %{id: 1, name: "lead"},
        %{id: 2, name: "reviewer"},
        %{id: 3, name: "builder"},
        %{id: 4, name: "scout"}
      ]

      rules = [
        %{from: 4, to: 2, policy: "allow"},
        %{from: 2, to: 1, policy: "allow"},
        %{from: 3, to: 2, policy: "allow"},
        %{from: 1, to: 3, policy: "allow"},
        %{from: 3, to: 1, policy: "route", via: 2},
        %{from: 4, to: 1, policy: "deny"}
      ]

      scout = AgentPromptProtocol.allowed_contacts(4, rules, agents, "review-1")
      assert scout =~ ~s("review-1-reviewer" -- reviewer)
      refute scout =~ ~s("review-1-lead")
      assert scout =~ "Do NOT message"

      builder = AgentPromptProtocol.allowed_contacts(3, rules, agents, "review-1")
      assert builder =~ "routed via reviewer"
    end
  end

  describe "allowed_contacts/5 merging" do
    test "a direct channel and a route to the same relay share one line", %{agents: agents} do
      rules = [
        %{from: 3, to: 2, policy: "allow"},
        %{from: 3, to: 1, policy: "route", via: 2}
      ]

      block = AgentPromptProtocol.allowed_contacts(3, rules, agents, "run-7")

      # One line for the reviewer's id, not two consecutive identical ids.
      assert length(Regex.scan(~r/"run-7-lead"/, block)) == 1
      assert block =~ "also relays to"
    end

    test "the merged line names both the relay and the destination", %{agents: agents} do
      rules = [
        %{from: 3, to: 2, policy: "allow"},
        %{from: 3, to: 1, policy: "route", via: 2}
      ]

      block = AgentPromptProtocol.allowed_contacts(3, rules, agents, "run-7")

      assert block =~ "lead"
      assert block =~ "coordinator (routed via lead)"
    end

    test "distinct ids stay on separate lines", %{agents: agents} do
      rules = [
        %{from: 1, to: 2, policy: "allow"},
        %{from: 1, to: 3, policy: "allow"}
      ]

      block = AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7")

      refute block =~ "also relays to"
    end
  end

  describe "authorize/3 and can_send?/3" do
    test "an allow rule authorizes that direction only" do
      rules = [%{from: 1, to: 2, policy: "allow"}]

      assert AgentPromptProtocol.can_send?(1, 2, rules)
      refute AgentPromptProtocol.can_send?(2, 1, rules)
    end

    test "nothing is permitted by default" do
      assert AgentPromptProtocol.authorize(1, 2, []) == {:error, :no_rule}
    end

    test "a deny rule is distinguishable from an absent one" do
      assert AgentPromptProtocol.authorize(1, 2, [%{from: 1, to: 2, policy: "deny"}]) ==
               {:error, :denied}

      assert AgentPromptProtocol.authorize(1, 2, []) == {:error, :no_rule}
    end

    test "deny beats allow in either order" do
      forward = [%{from: 1, to: 2, policy: "allow"}, %{from: 1, to: 2, policy: "deny"}]
      reverse = [%{from: 1, to: 2, policy: "deny"}, %{from: 1, to: 2, policy: "allow"}]

      assert AgentPromptProtocol.authorize(1, 2, forward) == {:error, :denied}
      assert AgentPromptProtocol.authorize(1, 2, reverse) == {:error, :denied}
    end

    test "a route rule authorizes the relay, not the destination" do
      rules = [%{from: 3, to: 1, policy: "route", via: 2}]

      refute AgentPromptProtocol.can_send?(3, 1, rules)
      assert AgentPromptProtocol.can_send?(3, 2, rules)
    end

    test "a route rule with no via authorizes nothing" do
      rules = [%{from: 3, to: 1, policy: "route"}]

      refute AgentPromptProtocol.can_send?(3, 1, rules)
      refute AgentPromptProtocol.can_send?(3, 2, rules)
    end

    test "rules for other senders do not leak" do
      rules = [%{from: 1, to: 2, policy: "allow"}]

      refute AgentPromptProtocol.can_send?(3, 2, rules)
    end

    test "the gate agrees with the prose it renders", %{agents: agents} do
      # The property that makes one rule set safe to use for both.
      rules = [
        %{from: 1, to: 2, policy: "allow"},
        %{from: 1, to: 3, policy: "deny"},
        %{from: 1, to: 4, policy: "route", via: 2}
      ]

      block = AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7")

      for agent <- agents, agent.id != 1 do
        sid = AgentPromptProtocol.session_id("run-7", agent.name)
        listed? = block =~ ~s("#{sid}")

        assert listed? == AgentPromptProtocol.can_send?(1, agent.id, rules),
               "#{agent.name}: block says #{listed?}, gate says the opposite"
      end
    end

    test "the review-chain wiring authorizes exactly what its prompt says" do
      rules = [
        %{from: 4, to: 2, policy: "allow"},
        %{from: 2, to: 1, policy: "allow"},
        %{from: 3, to: 2, policy: "allow"},
        %{from: 1, to: 3, policy: "allow"},
        %{from: 3, to: 1, policy: "route", via: 2},
        %{from: 4, to: 1, policy: "deny"}
      ]

      assert AgentPromptProtocol.can_send?(4, 2, rules)
      assert AgentPromptProtocol.authorize(4, 1, rules) == {:error, :denied}
      assert AgentPromptProtocol.can_send?(3, 2, rules)
      refute AgentPromptProtocol.can_send?(3, 1, rules)
      refute AgentPromptProtocol.can_send?(2, 4, rules)
    end
  end

  describe "authorize_session/5" do
    setup %{agents: agents} do
      rules = [
        %{from: 1, to: 2, policy: "allow"},
        %{from: 1, to: 3, policy: "deny"}
      ]

      {:ok, rules: rules, agents: agents, session: "run-7"}
    end

    test "authorizes by session id", ctx do
      assert AgentPromptProtocol.authorize_session(
               "run-7-coordinator",
               "run-7-lead",
               ctx.rules,
               ctx.agents,
               ctx.session
             ) == :ok
    end

    test "refuses a denied pair", ctx do
      assert AgentPromptProtocol.authorize_session(
               "run-7-coordinator",
               "run-7-builder",
               ctx.rules,
               ctx.agents,
               ctx.session
             ) == {:error, :denied}
    end

    test "reports an invented sender", ctx do
      assert AgentPromptProtocol.authorize_session(
               "run-7-ghost",
               "run-7-lead",
               ctx.rules,
               ctx.agents,
               ctx.session
             ) == {:error, :unknown_sender}
    end

    test "reports an invented recipient", ctx do
      assert AgentPromptProtocol.authorize_session(
               "run-7-coordinator",
               "run-7-ghost",
               ctx.rules,
               ctx.agents,
               ctx.session
             ) == {:error, :unknown_recipient}
    end

    test "an id from another run does not resolve", ctx do
      assert AgentPromptProtocol.authorize_session(
               "other-run-coordinator",
               "run-7-lead",
               ctx.rules,
               ctx.agents,
               ctx.session
             ) == {:error, :unknown_sender}
    end

    test "honours a configured separator", ctx do
      Application.put_env(:agent_prompt_protocol, :session_separator, ":")

      assert AgentPromptProtocol.authorize_session(
               "run-7:coordinator",
               "run-7:lead",
               ctx.rules,
               ctx.agents,
               ctx.session
             ) == :ok
    end
  end

  describe "recipients/2" do
    test "lists direct targets and relays, not routed destinations" do
      rules = [
        %{from: 1, to: 2, policy: "allow"},
        %{from: 1, to: 3, policy: "route", via: 4}
      ]

      assert AgentPromptProtocol.recipients(1, rules) == [2, 4]
    end

    test "excludes denied targets" do
      rules = [
        %{from: 1, to: 2, policy: "allow"},
        %{from: 1, to: 3, policy: "allow"},
        %{from: 1, to: 3, policy: "deny"}
      ]

      assert AgentPromptProtocol.recipients(1, rules) == [2]
    end

    test "a relay that is separately denied is excluded" do
      rules = [
        %{from: 1, to: 3, policy: "route", via: 2},
        %{from: 1, to: 2, policy: "deny"}
      ]

      assert AgentPromptProtocol.recipients(1, rules) == []
    end

    test "deduplicates" do
      rules = [
        %{from: 1, to: 2, policy: "allow"},
        %{from: 1, to: 3, policy: "route", via: 2}
      ]

      assert AgentPromptProtocol.recipients(1, rules) == [2]
    end

    test "is empty for an isolated slot" do
      assert AgentPromptProtocol.recipients(1, []) == []
    end

    test "agrees with can_send?/3" do
      rules = [
        %{from: 1, to: 2, policy: "allow"},
        %{from: 1, to: 3, policy: "deny"},
        %{from: 1, to: 4, policy: "route", via: 5}
      ]

      for slot <- AgentPromptProtocol.recipients(1, rules) do
        assert AgentPromptProtocol.can_send?(1, slot, rules)
      end
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
