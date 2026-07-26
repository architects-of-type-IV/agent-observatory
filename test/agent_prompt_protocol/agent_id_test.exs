defmodule AgentPromptProtocol.AgentIdTest do
  use ExUnit.Case, async: false

  alias AgentPromptProtocol.AgentId

  doctest AgentPromptProtocol.AgentId

  setup do
    on_exit(fn -> Application.delete_env(:agent_prompt_protocol, :id_kinds) end)
    :ok
  end

  describe "parse/1" do
    test "parses each default kind" do
      for kind <- [:mes, :pipeline, :planning] do
        assert {:ok, %AgentId{kind: ^kind, run_id: "r1", role: "lead"}} =
                 AgentId.parse("#{kind}-r1-lead")
      end
    end

    test "keeps the raw string" do
      assert {:ok, %AgentId{raw: "mes-r1-lead"}} = AgentId.parse("mes-r1-lead")
    end

    test "ignores trailing segments" do
      assert {:ok, %AgentId{role: "builder", run_id: "abc"}} =
               AgentId.parse("mes-abc-builder-2-extra")
    end

    test "rejects an unknown kind" do
      assert AgentId.parse("workshop-r1-lead") == :error
    end

    test "rejects too few segments" do
      assert AgentId.parse("mes-r1") == :error
      assert AgentId.parse("mes") == :error
      assert AgentId.parse("") == :error
    end

    test "rejects a non-binary" do
      assert AgentId.parse(nil) == :error
      assert AgentId.parse(:mes) == :error
    end

    test "honours configured kinds" do
      Application.put_env(:agent_prompt_protocol, :id_kinds, [:custom])

      assert {:ok, %AgentId{kind: :custom}} = AgentId.parse("custom-r1-lead")
      assert AgentId.parse("mes-r1-lead") == :error
    end

    test "an unknown kind does not need the atom to pre-exist" do
      # A to_existing_atom implementation would be sensitive to whether some
      # unrelated module happened to have created the atom first.
      assert AgentId.parse("neverbeforeseenkind-r1-lead") == :error
    end
  end

  describe "build/3 and format/1" do
    test "round-trips through parse" do
      id = AgentId.build(:pipeline, "abc123", "builder")

      assert AgentId.format(id) == "pipeline-abc123-builder"
      assert {:ok, ^id} = AgentId.parse(AgentId.format(id))
    end
  end

  describe "run_id/1" do
    test "extracts the run id" do
      assert AgentId.run_id("pipeline-abc123-builder") == {:ok, "abc123"}
    end

    test "reports a malformed id" do
      assert AgentId.run_id("nonsense") == :error
    end
  end

  describe "valid?/1" do
    test "distinguishes well-formed ids" do
      assert AgentId.valid?("mes-r1-lead")
      refute AgentId.valid?("mes-r1")
      refute AgentId.valid?("unknown-r1-lead")
    end
  end
end
