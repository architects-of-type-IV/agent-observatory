defmodule IchorWeb.SignalFeed.Renderers.Fallback do
  @moduledoc """
  Catch-all renderer for signals with no dedicated renderer.
  Displays the event topic and all data keys as kv badges.
  Never crashes regardless of signal shape.
  """
  use Phoenix.Component

  alias Ichor.Events.Event
  alias IchorWeb.SignalFeed.Primitives

  attr :seq, :integer, required: true
  attr :event, :any, required: true

  def render(%{event: %Event{topic: topic, data: data}} = assigns) do
    assigns =
      assign(assigns,
        topic: topic,
        pairs: data_to_pairs(data)
      )

    ~H"""
    <span class="text-[10px] text-muted font-mono mr-1">{@topic}</span>
    <span :for={p <- @pairs} class="mr-1">
      <Primitives.kv key={p.key} value={p.val} />
    </span>
    """
  end

  def render(assigns) do
    ~H"""
    <span class="text-[10px] text-muted font-mono mr-1">unknown</span>
    """
  end

  defp data_to_pairs(nil), do: []

  defp data_to_pairs(data) when is_map(data) do
    data
    |> Enum.map(fn {k, v} -> %{key: to_string(k), val: format_value(v)} end)
    |> Enum.sort_by(& &1.key)
  end

  defp data_to_pairs(_), do: []

  defp format_value(nil), do: "nil"

  defp format_value(v) when is_binary(v) and byte_size(v) > 60,
    do: String.slice(v, 0, 57) <> "..."

  defp format_value(v) when is_binary(v), do: v
  defp format_value(v) when is_atom(v), do: Atom.to_string(v)
  defp format_value(v) when is_number(v), do: to_string(v)
  defp format_value(v) when is_list(v), do: "[#{length(v)} items]"

  defp format_value(v) when is_map(v) do
    v
    |> inspect(limit: 3, pretty: false)
    |> String.slice(0, 60)
  end

  defp format_value(v), do: inspect(v, limit: 3, printable_limit: 20) |> String.slice(0, 60)
end
