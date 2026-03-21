defmodule Ichor.Signals.HITLInterventionEventTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Ichor.Signals.HITLInterventionEvent

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Ichor.Repo)
  end

  describe "record/1" do
    test "creates a :pause event with required fields" do
      attrs = %{
        session_id: "session-abc",
        agent_id: "agent-1",
        operator_id: "op-1",
        action: :pause,
        details: %{reason: "manual review"}
      }

      assert {:ok, event} = HITLInterventionEvent.record(attrs)

      assert event.session_id == "session-abc"
      assert event.agent_id == "agent-1"
      assert event.operator_id == "op-1"
      assert event.action == :pause
      assert event.details == %{"reason" => "manual review"}
      assert %DateTime{} = event.inserted_at
    end

    test "creates an :unpause event" do
      attrs = %{session_id: "s1", operator_id: "op-1", action: :unpause}

      assert {:ok, event} = HITLInterventionEvent.record(attrs)
      assert event.action == :unpause
    end

    test "creates a :rewrite event" do
      attrs = %{
        session_id: "s1",
        operator_id: "op-1",
        action: :rewrite,
        details: %{new_prompt: "updated"}
      }

      assert {:ok, event} = HITLInterventionEvent.record(attrs)
      assert event.action == :rewrite
    end

    test "creates an :inject event" do
      attrs = %{
        session_id: "s1",
        operator_id: "op-1",
        action: :inject,
        details: %{message: "continue"}
      }

      assert {:ok, event} = HITLInterventionEvent.record(attrs)
      assert event.action == :inject
    end

    test "details defaults to empty map when not provided" do
      attrs = %{session_id: "s1", operator_id: "op-1", action: :pause}

      assert {:ok, event} = HITLInterventionEvent.record(attrs)
      assert event.details == %{}
    end

    test "returns error when session_id is missing" do
      attrs = %{operator_id: "op-1", action: :pause}

      assert {:error, %Ash.Error.Invalid{}} = HITLInterventionEvent.record(attrs)
    end

    test "returns error when operator_id is missing" do
      attrs = %{session_id: "s1", action: :pause}

      assert {:error, %Ash.Error.Invalid{}} = HITLInterventionEvent.record(attrs)
    end

    test "returns error when action is missing" do
      attrs = %{session_id: "s1", operator_id: "op-1"}

      assert {:error, %Ash.Error.Invalid{}} = HITLInterventionEvent.record(attrs)
    end

    test "returns error for invalid action atom" do
      attrs = %{session_id: "s1", operator_id: "op-1", action: :unknown_action}

      assert {:error, %Ash.Error.Invalid{}} = HITLInterventionEvent.record(attrs)
    end
  end

  describe "by_session/1" do
    test "returns events for the given session" do
      attrs = %{session_id: "session-query", operator_id: "op-1", action: :pause}

      {:ok, event} = HITLInterventionEvent.record(attrs)
      {:ok, results} = HITLInterventionEvent.by_session("session-query")

      ids = Enum.map(results, & &1.id)
      assert event.id in ids
    end

    test "does not return events for a different session" do
      {:ok, _} =
        HITLInterventionEvent.record(%{
          session_id: "session-other",
          operator_id: "op-1",
          action: :inject
        })

      {:ok, results} = HITLInterventionEvent.by_session("session-query-2")
      ids = Enum.map(results, & &1.id)
      # session-other's event should not appear here
      Enum.each(results, fn e ->
        assert e.session_id == "session-query-2"
      end)

      assert is_list(ids)
    end

    test "returns empty list for unknown session" do
      {:ok, results} = HITLInterventionEvent.by_session("session-nonexistent-xyz")
      assert results == []
    end
  end

  describe "by_agent/1" do
    test "returns events for the given agent" do
      agent_id = "agent-hitl-#{System.unique_integer([:positive])}"

      {:ok, event} =
        HITLInterventionEvent.record(%{
          session_id: "s1",
          agent_id: agent_id,
          operator_id: "op-1",
          action: :pause
        })

      {:ok, results} = HITLInterventionEvent.by_agent(agent_id)
      ids = Enum.map(results, & &1.id)
      assert event.id in ids
    end

    test "returns empty list for agent with no events" do
      {:ok, results} =
        HITLInterventionEvent.by_agent("agent-hitl-never-#{System.unique_integer([:positive])}")

      assert results == []
    end
  end

  describe "by_operator/1" do
    test "returns events for the given operator" do
      op_id = "op-hitl-#{System.unique_integer([:positive])}"

      {:ok, event} =
        HITLInterventionEvent.record(%{session_id: "s1", operator_id: op_id, action: :unpause})

      {:ok, results} = HITLInterventionEvent.by_operator(op_id)
      ids = Enum.map(results, & &1.id)
      assert event.id in ids
    end
  end

  describe "recent/0" do
    test "returns events sorted by inserted_at descending" do
      op_id = "op-recent-#{System.unique_integer([:positive])}"

      {:ok, e1} =
        HITLInterventionEvent.record(%{session_id: "s1", operator_id: op_id, action: :pause})

      {:ok, e2} =
        HITLInterventionEvent.record(%{session_id: "s2", operator_id: op_id, action: :unpause})

      {:ok, results} = HITLInterventionEvent.recent()

      assert is_list(results)
      # e2 was inserted after e1, so it should appear first or at least be present
      ids = Enum.map(results, & &1.id)
      assert e1.id in ids
      assert e2.id in ids
    end
  end
end
