defmodule Ichor.Archon.Chat.CommandParserTest do
  use ExUnit.Case, async: true

  alias Ichor.Archon.Chat.CommandParser

  test "parses command with no arguments" do
    assert {:ok, %{command: "/agents", remainder: nil, raw: "/agents"}} =
             CommandParser.parse("/agents")
  end

  test "parses command with trailing arguments" do
    assert {:ok, %{command: "/events", remainder: "alpha 5"}} =
             CommandParser.parse("  /events alpha 5  ")
  end
end
