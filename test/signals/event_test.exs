defmodule Signals.EventTest do
  use ExUnit.Case, async: true

  alias Signals.Event

  doctest Signals.Event

  describe "new/2" do
    test "fills id, time, and source" do
      event = Event.new("agent.tool.completed")

      assert event.type == "agent.tool.completed"
      assert is_binary(event.id)
      assert %DateTime{} = event.time
      assert event.source == "backend"
      assert event.specversion == "1.0"
    end

    test "ids are unique" do
      refute Event.new("a.b").id == Event.new("a.b").id
    end

    test "carries subject and data" do
      event = Event.new("a.b", subject: "agent-1", data: %{tool: "Read"})

      assert event.subject == "agent-1"
      assert event.data == %{tool: "Read"}
    end
  end

  describe "position" do
    test "is nil without an extension" do
      assert Event.position(Event.new("a.b")) == nil
    end

    test "round-trips through with_position/2" do
      assert Event.new("a.b") |> Event.with_position(42) |> Event.position() == 42
    end
  end

  describe "emission?/1 and signal_name/1" do
    test "recognises an emission" do
      assert Event.emission?(Event.new("signal.loop_detected"))
      assert Event.signal_name(Event.new("signal.loop_detected")) == "loop_detected"
    end

    test "an ordinary event is not an emission" do
      refute Event.emission?(Event.new("agent.tool.completed"))
      assert Event.signal_name(Event.new("agent.tool.completed")) == nil
    end
  end

  describe "CloudEvents round-trip" do
    test "to_cloudevent produces the required attributes" do
      map = Event.new("a.b", subject: "s", data: %{x: 1}) |> Event.to_cloudevent()

      assert map["specversion"] == "1.0"
      assert map["type"] == "a.b"
      assert map["subject"] == "s"
      assert map["source"] == "backend"
      assert is_binary(map["id"])
      assert is_binary(map["time"])
    end

    test "omits absent optional attributes rather than emitting nulls" do
      map = Event.new("a.b") |> Event.to_cloudevent()

      refute Map.has_key?(map, "subject")
      refute Map.has_key?(map, "data")
    end

    test "extensions are flattened to top level, as CloudEvents specifies" do
      map = Event.new("a.b", extensions: %{position: 7}) |> Event.to_cloudevent()

      assert map["position"] == 7
    end

    test "round-trips" do
      original = Event.new("a.b", subject: "s", data: %{"x" => 1}, extensions: %{position: 3})

      assert {:ok, parsed} = original |> Event.to_cloudevent() |> Event.from_cloudevent()
      assert parsed.type == original.type
      assert parsed.subject == original.subject
      assert parsed.data == original.data
      assert Event.position(parsed) == 3
      assert DateTime.compare(parsed.time, original.time) == :eq
    end

    test "unknown top-level keys become extensions" do
      {:ok, event} =
        Event.from_cloudevent(%{
          "id" => "1",
          "type" => "a.b",
          "source" => "x",
          "traceparent" => "00-abc"
        })

      assert event.extensions["traceparent"] == "00-abc" or
               event.extensions[:traceparent] == "00-abc"
    end

    test "reports a missing required attribute" do
      assert {:error, {:missing, "type"}} = Event.from_cloudevent(%{"id" => "1", "source" => "x"})
    end

    test "rejects a non-map" do
      assert {:error, :not_a_map} = Event.from_cloudevent("nope")
    end

    test "defaults time when absent" do
      assert {:ok, event} =
               Event.from_cloudevent(%{"id" => "1", "type" => "a.b", "source" => "x"})

      assert %DateTime{} = event.time
    end
  end
end
