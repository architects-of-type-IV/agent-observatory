defmodule Observatory.Mesh.DecisionLogTest do
  use ExUnit.Case, async: true

  alias Observatory.Mesh.DecisionLog

  @valid_params %{
    "meta" => %{
      "trace_id" => "550e8400-e29b-41d4-a716-446655440000",
      "timestamp" => "2026-02-22T12:00:00Z"
    },
    "identity" => %{
      "agent_id" => "agent-001",
      "agent_type" => "reasoning",
      "capability_version" => "1.0.0"
    },
    "cognition" => %{
      "intent" => "classify_input",
      "reasoning_chain" => ["step 1", "step 2"],
      "confidence_score" => 0.95,
      "strategy_used" => "CoT",
      "entropy_score" => 0.3
    },
    "action" => %{
      "status" => "success",
      "tool_call" => "classify",
      "tool_input" => ~s({"text": "hello"}),
      "tool_output_summary" => "classified as greeting"
    },
    "state_delta" => %{
      "added_to_memory" => ["greeting detected"],
      "tokens_consumed" => 150,
      "cumulative_session_cost" => 0.002
    },
    "control" => %{
      "hitl_required" => false,
      "interrupt_signal" => nil,
      "is_terminal" => false
    }
  }

  describe "changeset/2 with valid params" do
    test "all required fields present produces a valid changeset" do
      changeset = DecisionLog.changeset(%DecisionLog{}, @valid_params)
      assert changeset.valid?
    end

    test "apply_changes returns a %DecisionLog{} struct with all sections" do
      changeset = DecisionLog.changeset(%DecisionLog{}, @valid_params)
      log = Ecto.Changeset.apply_changes(changeset)

      assert %DecisionLog{} = log
      assert log.meta.trace_id == "550e8400-e29b-41d4-a716-446655440000"
      assert log.identity.agent_id == "agent-001"
      assert log.cognition.intent == "classify_input"
      assert log.action.status == :success
      assert log.state_delta.tokens_consumed == 150
      assert log.control.hitl_required == false
    end
  end

  describe "changeset/2 missing required meta fields" do
    test "missing meta.trace_id fails validation" do
      params = put_in(@valid_params, ["meta", "trace_id"], nil)
      changeset = DecisionLog.changeset(%DecisionLog{}, params)
      refute changeset.valid?

      meta_changeset = changeset.changes.meta
      assert {:trace_id, {"can't be blank", [validation: :required]}} in meta_changeset.errors
    end

    test "missing meta.timestamp fails validation" do
      params = put_in(@valid_params, ["meta", "timestamp"], nil)
      changeset = DecisionLog.changeset(%DecisionLog{}, params)
      refute changeset.valid?

      meta_changeset = changeset.changes.meta
      assert {:timestamp, {"can't be blank", [validation: :required]}} in meta_changeset.errors
    end
  end

  describe "changeset/2 missing required identity fields" do
    test "missing identity.agent_id fails validation" do
      params = put_in(@valid_params, ["identity", "agent_id"], nil)
      changeset = DecisionLog.changeset(%DecisionLog{}, params)
      refute changeset.valid?

      identity_changeset = changeset.changes.identity
      assert {:agent_id, {"can't be blank", [validation: :required]}} in identity_changeset.errors
    end

    test "missing identity.agent_type fails validation" do
      params = put_in(@valid_params, ["identity", "agent_type"], nil)
      changeset = DecisionLog.changeset(%DecisionLog{}, params)
      refute changeset.valid?

      identity_changeset = changeset.changes.identity
      assert {:agent_type, {"can't be blank", [validation: :required]}} in identity_changeset.errors
    end

    test "missing identity.capability_version fails validation" do
      params = put_in(@valid_params, ["identity", "capability_version"], nil)
      changeset = DecisionLog.changeset(%DecisionLog{}, params)
      refute changeset.valid?

      identity_changeset = changeset.changes.identity

      assert {:capability_version, {"can't be blank", [validation: :required]}} in identity_changeset.errors
    end
  end

  describe "changeset/2 missing required cognition fields" do
    test "missing cognition.intent fails validation when cognition section present" do
      params = put_in(@valid_params, ["cognition"], %{"strategy_used" => "CoT"})
      changeset = DecisionLog.changeset(%DecisionLog{}, params)
      refute changeset.valid?

      cognition_changeset = changeset.changes.cognition
      assert {:intent, {"can't be blank", [validation: :required]}} in cognition_changeset.errors
    end
  end

  describe "changeset/2 missing required action fields" do
    test "missing action.status fails validation when action section present" do
      params = put_in(@valid_params, ["action"], %{"tool_call" => "classify"})
      changeset = DecisionLog.changeset(%DecisionLog{}, params)
      refute changeset.valid?

      action_changeset = changeset.changes.action
      assert {:status, {"can't be blank", [validation: :required]}} in action_changeset.errors
    end
  end

  describe "changeset/2 optional section handling" do
    test "absent cognition section produces valid changeset" do
      params = Map.delete(@valid_params, "cognition")
      changeset = DecisionLog.changeset(%DecisionLog{}, params)
      assert changeset.valid?

      log = Ecto.Changeset.apply_changes(changeset)
      assert log.cognition == nil
    end

    test "absent state_delta section produces valid changeset" do
      params = Map.delete(@valid_params, "state_delta")
      changeset = DecisionLog.changeset(%DecisionLog{}, params)
      assert changeset.valid?

      log = Ecto.Changeset.apply_changes(changeset)
      assert log.state_delta == nil
    end

    test "absent control section produces valid changeset" do
      params = Map.delete(@valid_params, "control")
      changeset = DecisionLog.changeset(%DecisionLog{}, params)
      assert changeset.valid?

      log = Ecto.Changeset.apply_changes(changeset)
      assert log.control == nil
    end

    test "minimal payload with only required fields is valid" do
      minimal = %{
        "meta" => %{
          "trace_id" => "550e8400-e29b-41d4-a716-446655440000",
          "timestamp" => "2026-02-22T12:00:00Z"
        },
        "identity" => %{
          "agent_id" => "agent-001",
          "agent_type" => "reasoning",
          "capability_version" => "1.0.0"
        },
        "cognition" => %{
          "intent" => "classify_input"
        },
        "action" => %{
          "status" => "success"
        }
      }

      changeset = DecisionLog.changeset(%DecisionLog{}, minimal)
      assert changeset.valid?
    end
  end

  describe "parent_step_id root detection" do
    test "nil parent_step_id produces valid changeset with meta.parent_step_id == nil" do
      params = put_in(@valid_params, ["meta", "parent_step_id"], nil)
      changeset = DecisionLog.changeset(%DecisionLog{}, params)
      assert changeset.valid?

      log = Ecto.Changeset.apply_changes(changeset)
      assert log.meta.parent_step_id == nil
    end

    test "empty string parent_step_id is trimmed to nil" do
      params = put_in(@valid_params, ["meta", "parent_step_id"], "")
      changeset = DecisionLog.changeset(%DecisionLog{}, params)
      assert changeset.valid?

      log = Ecto.Changeset.apply_changes(changeset)
      assert log.meta.parent_step_id == nil
    end

    test "valid UUID string parent_step_id is preserved" do
      uuid = "7d4e9c2b-1f38-4a6d-b8e5-0c123456789a"
      params = put_in(@valid_params, ["meta", "parent_step_id"], uuid)
      changeset = DecisionLog.changeset(%DecisionLog{}, params)
      assert changeset.valid?

      log = Ecto.Changeset.apply_changes(changeset)
      assert log.meta.parent_step_id == uuid
    end

    test "root?/1 returns true for struct with meta.parent_step_id: nil" do
      log = %DecisionLog{meta: %DecisionLog.Meta{parent_step_id: nil}}
      assert DecisionLog.root?(log) == true
    end

    test "root?/1 returns false for struct with meta.parent_step_id: some-uuid" do
      log = %DecisionLog{meta: %DecisionLog.Meta{parent_step_id: "some-uuid"}}
      assert DecisionLog.root?(log) == false
    end
  end

  describe "major_version/1" do
    test "extracts major version from 1.0.0" do
      log = %DecisionLog{identity: %DecisionLog.Identity{capability_version: "1.0.0"}}
      assert DecisionLog.major_version(log) == 1
    end

    test "extracts major version from 2.3.1" do
      log = %DecisionLog{identity: %DecisionLog.Identity{capability_version: "2.3.1"}}
      assert DecisionLog.major_version(log) == 2
    end

    test "returns nil for struct without identity" do
      log = %DecisionLog{identity: nil}
      assert DecisionLog.major_version(log) == nil
    end
  end

  describe "put_gateway_entropy_score/2" do
    test "overwrites entropy_score when cognition is present" do
      log =
        @valid_params
        |> (&DecisionLog.changeset(%DecisionLog{}, &1)).()
        |> Ecto.Changeset.apply_changes()

      assert log.cognition.entropy_score == 0.3

      updated = DecisionLog.put_gateway_entropy_score(log, 0.15)
      assert updated.cognition.entropy_score == 0.15
    end

    test "returns log unchanged when cognition is nil" do
      log = %DecisionLog{cognition: nil}
      result = DecisionLog.put_gateway_entropy_score(log, 0.15)
      assert result.cognition == nil
    end
  end

  describe "from_json/1" do
    test "valid string-keyed map returns {:ok, %DecisionLog{}}" do
      assert {:ok, %DecisionLog{} = log} = DecisionLog.from_json(@valid_params)
      assert log.meta.trace_id == "550e8400-e29b-41d4-a716-446655440000"
      assert log.identity.agent_id == "agent-001"
      assert log.cognition.intent == "classify_input"
    end

    test "map with invalid action.status returns {:error, changeset}" do
      params = put_in(@valid_params, ["action", "status"], "timeout")
      assert {:error, changeset} = DecisionLog.from_json(params)
      refute changeset.valid?
    end

    test "map with empty meta (present but missing required fields) returns {:error, changeset}" do
      params = Map.put(@valid_params, "meta", %{})
      assert {:error, changeset} = DecisionLog.from_json(params)
      refute changeset.valid?
    end
  end

  describe "UI derivation anchor field regression" do
    setup do
      log =
        @valid_params
        |> (&DecisionLog.changeset(%DecisionLog{}, &1)).()
        |> Ecto.Changeset.apply_changes()

      {:ok, log: log}
    end

    test "all 6 anchor fields are accessible without raising", %{log: log} do
      assert is_binary(log.meta.parent_step_id) or is_nil(log.meta.parent_step_id)
      assert is_list(log.cognition.reasoning_chain)
      assert is_float(log.cognition.entropy_score)
      assert is_float(log.state_delta.cumulative_session_cost)
      assert is_boolean(log.control.hitl_required)
      assert is_boolean(log.control.is_terminal)
    end

    test "Cognition schema fields include :reasoning_chain and :entropy_score" do
      fields = DecisionLog.Cognition.__schema__(:fields)
      assert :reasoning_chain in fields
      assert :entropy_score in fields
    end

    test "StateDelta schema fields include :cumulative_session_cost" do
      fields = DecisionLog.StateDelta.__schema__(:fields)
      assert :cumulative_session_cost in fields
    end

    test "Control schema fields include :hitl_required and :is_terminal" do
      fields = DecisionLog.Control.__schema__(:fields)
      assert :hitl_required in fields
      assert :is_terminal in fields
    end

    test "Meta schema fields include :parent_step_id" do
      fields = DecisionLog.Meta.__schema__(:fields)
      assert :parent_step_id in fields
    end
  end

  describe "action.status enum validation" do
    for status <- ~w(success failure pending skipped) do
      test "valid status #{status} passes validation" do
        params = put_in(@valid_params, ["action", "status"], unquote(status))
        changeset = DecisionLog.changeset(%DecisionLog{}, params)
        assert changeset.valid?

        log = Ecto.Changeset.apply_changes(changeset)
        assert log.action.status == String.to_existing_atom(unquote(status))
      end
    end

    test "invalid status 'timeout' is rejected" do
      params = put_in(@valid_params, ["action", "status"], "timeout")
      changeset = DecisionLog.changeset(%DecisionLog{}, params)
      refute changeset.valid?

      action_changeset = changeset.changes.action
      assert {:status, {"is invalid", _}} = List.keyfind(action_changeset.errors, :status, 0)
    end
  end
end
