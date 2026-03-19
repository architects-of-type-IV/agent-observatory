defmodule Ichor.Gateway.TargetTest do
  use ExUnit.Case, async: true

  alias Ichor.Gateway.Target

  test "normalizes shorthand targets to canonical gateway channels" do
    assert Target.normalize("alpha") == "agent:alpha"
    assert Target.normalize("member:uuid-1") == "session:uuid-1"
    assert Target.normalize("all") == "fleet:all"
    assert Target.normalize("lead:research") == "role:lead"
    assert Target.normalize("team:blue") == "team:blue"
  end

  test "extracts ids from canonical channels" do
    assert Target.extract_id("agent:alpha") == "alpha"
    assert Target.extract_id("session:uuid-1") == "uuid-1"
    assert Target.extract_id("role:lead") == "lead"
  end
end
