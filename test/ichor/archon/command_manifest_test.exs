defmodule Ichor.Archon.CommandManifestTest do
  use ExUnit.Case, async: true

  alias Ichor.Archon.CommandManifest

  test "exposes manager-first quick actions" do
    assert [%{cmd: "manager"}, %{cmd: "attention"} | _] = CommandManifest.quick_actions()
  end

  test "builds unknown command help from grouped usage" do
    help = CommandManifest.unknown_command_help("/wat")

    assert help =~ "Unknown command: /wat"
    assert help =~ "Observation:"
    assert help =~ "Manager:"
    assert help =~ "/manager /attention"
  end
end
