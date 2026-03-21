defmodule Ichor.Signals.EmitTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Ichor.Signals

  describe "emit/2" do
    test "returns :ok for a valid signal name and data map" do
      assert :ok = Signals.emit(:agent_started, %{session_id: "s1", role: "worker", team: "t1"})
    end

    test "returns :ok for a valid signal name with empty map" do
      assert :ok = Signals.emit(:fleet_changed, %{})
    end

    test "returns :ok when data is nil (coerces to empty map)" do
      assert :ok = Signals.emit(:agent_started, nil)
    end

    test "returns :ok for session_ended signal" do
      assert :ok = Signals.emit(:session_ended, %{session_id: "s-abc", status: "done"})
    end

    test "returns :ok for heartbeat signal" do
      assert :ok = Signals.emit(:heartbeat, %{count: 1})
    end
  end

  describe "emit/3 (scoped, dynamic signals only)" do
    test "returns :ok for a dynamic signal with scope_id" do
      # agent_event is dynamic: true in the catalog
      assert :ok = Signals.emit(:agent_event, "agent-scope-1", %{event: %{type: "tick"}})
    end

    test "returns :ok for terminal_output dynamic signal" do
      assert :ok =
               Signals.emit(:terminal_output, "agent-scope-2", %{session_id: "s1", output: "line"})
    end

    test "raises ArgumentError for non-dynamic signal with scope_id" do
      assert_raise ArgumentError, ~r/not dynamic/, fn ->
        Signals.emit(:agent_started, "agent-scope-3", %{})
      end
    end
  end

  describe "subscribe/1 and unsubscribe/1" do
    test "subscribe to a signal name returns :ok" do
      assert :ok = Signals.subscribe(:agent_started)
    end

    test "subscribe to a category name returns :ok" do
      assert :ok = Signals.subscribe(:fleet)
    end

    test "unsubscribe returns :ok after subscribe" do
      Signals.subscribe(:fleet_changed)
      assert :ok = Signals.unsubscribe(:fleet_changed)
    end
  end
end
