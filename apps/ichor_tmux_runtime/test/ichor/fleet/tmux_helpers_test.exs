defmodule Ichor.Fleet.TmuxHelpersTest do
  use ExUnit.Case, async: true

  alias Ichor.Fleet.TmuxHelpers

  test "maps coordinator capabilities to role and permissions" do
    assert TmuxHelpers.capability_to_role("coordinator") == :coordinator
    assert :kill in TmuxHelpers.capabilities_for("coordinator")

    args = TmuxHelpers.add_permission_args(["--model", "sonnet"], "coordinator")

    assert "--dangerously-skip-permissions" in args
  end
end
