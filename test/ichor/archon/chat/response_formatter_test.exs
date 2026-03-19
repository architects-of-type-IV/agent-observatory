defmodule Ichor.Archon.Chat.ResponseFormatterTest do
  use ExUnit.Case, async: true

  alias Ichor.Archon.Chat.ResponseFormatter

  test "extracts plain string content" do
    assert ResponseFormatter.extract(%{last_message: %{content: "hello"}}) == "hello"
  end

  test "extracts multipart content" do
    assert ResponseFormatter.extract(%{last_message: %{content: [%{content: "one"}, "two"]}}) ==
             "one\ntwo"
  end

  test "falls back when no response is present" do
    assert ResponseFormatter.extract(%{}) == "No response."
  end
end
