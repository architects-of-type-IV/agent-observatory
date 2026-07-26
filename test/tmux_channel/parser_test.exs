defmodule TmuxChannel.ParserTest do
  use ExUnit.Case, async: true

  alias TmuxChannel.Parser

  doctest TmuxChannel.Parser

  describe "split_lines/1" do
    test "splits on newlines and drops blanks" do
      assert Parser.split_lines("a\nb\n\nc\n") == ["a", "b", "c"]
    end

    test "returns an empty list for empty output" do
      assert Parser.split_lines("") == []
      assert Parser.split_lines("\n\n") == []
    end
  end

  describe "parse_pane_line/1" do
    test "parses the four-field form" do
      assert Parser.parse_pane_line("%3\tteam-a\tbuilder\t4821") ==
               %{pane_id: "%3", session: "team-a", title: "builder", pid: "4821"}
    end

    test "parses the three-field form with a nil pid" do
      assert Parser.parse_pane_line("%3\tteam-a\tbuilder") ==
               %{pane_id: "%3", session: "team-a", title: "builder", pid: nil}
    end

    test "returns nil for too few fields" do
      assert Parser.parse_pane_line("%3\tteam-a") == nil
      assert Parser.parse_pane_line("") == nil
    end

    test "returns nil for too many fields" do
      assert Parser.parse_pane_line("a\tb\tc\td\te") == nil
    end

    test "keeps an empty title rather than dropping the pane" do
      assert Parser.parse_pane_line("%1\tsess\t\t99") ==
               %{pane_id: "%1", session: "sess", title: "", pid: "99"}
    end
  end

  describe "parse_panes/1" do
    test "drops malformed lines and keeps the rest" do
      output = "%1\ts\tone\t1\ngarbage\n%2\ts\ttwo\t2\n"

      assert Parser.parse_panes(output) == [
               %{pane_id: "%1", session: "s", title: "one", pid: "1"},
               %{pane_id: "%2", session: "s", title: "two", pid: "2"}
             ]
    end

    test "returns an empty list when nothing parses" do
      assert Parser.parse_panes("garbage\nmore garbage\n") == []
    end
  end
end
