defmodule Ichor.Tools.GenesisFormatterTest do
  use ExUnit.Case, async: true

  alias Ichor.Tools.GenesisFormatter

  test "split_csv trims and drops empty values" do
    assert GenesisFormatter.split_csv("a, b, ,c") == ["a", "b", "c"]
    assert GenesisFormatter.split_csv(nil) == []
  end

  test "parse_enum maps strings and preserves atoms" do
    mapping = %{"accepted" => :accepted}

    assert GenesisFormatter.parse_enum("accepted", :pending, mapping) == :accepted
    assert GenesisFormatter.parse_enum(:draft, :pending, mapping) == :draft
    assert GenesisFormatter.parse_enum(nil, :pending, mapping) == :pending
  end

  test "summarize stringifies atoms and lists" do
    record = %{id: "1", status: :accepted, tags: ["a", "b"]}

    assert GenesisFormatter.summarize(record, [:status, :tags]) == %{
             "id" => "1",
             "status" => "accepted",
             "tags" => "a, b"
           }
  end
end
