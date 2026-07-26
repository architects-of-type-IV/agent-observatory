defmodule Signals.TopicTest do
  use ExUnit.Case, async: true

  alias Signals.Topic

  doctest Signals.Topic

  describe "match?/2" do
    test "exact types match exactly" do
      assert Topic.match?("agent.tool.completed", "agent.tool.completed")
      refute Topic.match?("agent.tool.failed", "agent.tool.completed")
    end

    test "a trailing wildcard spans any depth" do
      assert Topic.match?("agent.crashed", "agent.*")
      assert Topic.match?("agent.tool.completed", "agent.*")
      assert Topic.match?("agent.tool.budget.exhausted", "agent.*")
    end

    test "the wildcard respects segment boundaries" do
      refute Topic.match?("agents.crashed", "agent.*")
      refute Topic.match?("agentx.crashed", "agent.*")
    end

    test "a bare prefix does not match its own family without the wildcard" do
      refute Topic.match?("agent.crashed", "agent")
    end

    test "the prefix itself is not matched by its wildcard" do
      refute Topic.match?("agent", "agent.*")
    end

    test "* matches everything" do
      assert Topic.match?("anything", "*")
      assert Topic.match?("deeply.nested.type", "*")
    end

    test "mid-pattern wildcards are treated literally" do
      refute Topic.match?("agent.tool.completed", "agent.*.completed")
    end

    test "non-binaries do not match" do
      refute Topic.match?(nil, "agent.*")
      refute Topic.match?("agent.crashed", nil)
    end
  end

  describe "matches_any?/2" do
    test "true when any pattern matches" do
      assert Topic.matches_any?("agent.crashed", ["pipeline.*", "agent.*"])
    end

    test "false when none match" do
      refute Topic.matches_any?("system.started", ["agent.*", "pipeline.*"])
    end

    test "an empty pattern list matches nothing" do
      refute Topic.matches_any?("agent.crashed", [])
    end
  end

  describe "emission_type/1" do
    test "namespaces a signal name" do
      assert Topic.emission_type("loop_detected") == "signal.loop_detected"
      assert Topic.emission_type(:loop_detected) == "signal.loop_detected"
    end
  end

  describe "meta?/1" do
    test "detects subscription to emissions" do
      assert Topic.meta?(["signal.*"])
      assert Topic.meta?(["signal.loop_detected"])
      assert Topic.meta?(["*"])
    end

    test "ordinary topics are not meta" do
      refute Topic.meta?(["agent.*", "pipeline.job.failed"])
      refute Topic.meta?([])
    end
  end
end
