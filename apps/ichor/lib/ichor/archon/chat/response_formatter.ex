defmodule Ichor.Archon.Chat.ResponseFormatter do
  @moduledoc """
  Normalizes LangChain output into the final Archon response string.
  """

  @spec extract(term()) :: String.t()
  def extract(%{last_message: %{content: content}}) when is_binary(content), do: content

  def extract(%{last_message: %{content: parts}}) when is_list(parts) do
    Enum.map_join(parts, "\n", &content_part_text/1)
  end

  def extract(_), do: "No response."

  defp content_part_text(%{content: text}) when is_binary(text), do: text
  defp content_part_text(text) when is_binary(text), do: text
  defp content_part_text(other), do: inspect(other)
end
