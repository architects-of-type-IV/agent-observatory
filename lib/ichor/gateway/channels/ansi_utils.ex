defmodule Ichor.Gateway.Channels.AnsiUtils do
  @moduledoc false

  @doc "Strip ANSI escape sequences from a string."
  @spec strip_ansi(String.t()) :: String.t()
  def strip_ansi(text) do
    Regex.replace(~r/\e\[[0-9;]*[a-zA-Z]/, text, "")
  end
end
