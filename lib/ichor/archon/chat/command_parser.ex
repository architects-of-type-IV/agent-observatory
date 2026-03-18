defmodule Ichor.Archon.Chat.CommandParser do
  @moduledoc """
  Parses Archon slash commands into normalized command maps.
  """

  @spec parse(String.t()) :: {:ok, map()}
  def parse(input) when is_binary(input) do
    trimmed = String.trim(input)
    [command | rest] = String.split(trimmed, " ", parts: 2)
    remainder = List.first(rest)

    {:ok, %{raw: trimmed, command: command, remainder: remainder}}
  end
end
