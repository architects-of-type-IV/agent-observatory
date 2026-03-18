defmodule IchorWeb.Markdown do
  @moduledoc false

  @doc "Render markdown text to safe HTML via Earmark."
  @spec render(term()) :: Phoenix.HTML.safe()
  def render(nil), do: Phoenix.HTML.raw("")
  def render(""), do: Phoenix.HTML.raw("")

  def render(text) when is_binary(text) do
    text
    |> String.slice(0, 2000)
    |> Earmark.as_html!(compact_output: true, smartypants: false)
    |> Phoenix.HTML.raw()
  end

  def render(other), do: Phoenix.HTML.raw(to_string(other))
end
