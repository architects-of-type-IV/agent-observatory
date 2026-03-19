defmodule IchorWeb.SignalFeed.Renderers.Fallback do
  @moduledoc """
  Catch-all renderer for signals with no dedicated renderer.
  Displays domain:name and the first few data keys as kv badges.
  Never crashes regardless of signal shape.
  """
  use Phoenix.Component

  alias Ichor.Signals.Message
  alias IchorWeb.SignalFeed.Primitives

  attr :seq, :integer, required: true
  attr :message, :any, required: true

  def render(%{message: %Message{domain: domain, name: name, data: data}} = assigns) do
    assigns = assign(assigns, :pairs, build_pairs(domain, name, data))

    ~H"""
    <span class="text-[10px] text-muted font-mono mr-1">{@message.domain}:{@message.name}</span>
    <span :for={{k, v} <- @pairs}>
      <Primitives.kv key={k} value={v} />
    </span>
    """
  end

  defp build_pairs(domain, _name, data) when is_map(data) do
    pairs =
      data
      |> Map.keys()
      |> Enum.take(4)
      |> Enum.map(fn k -> {to_string(k), short_val(Map.get(data, k))} end)

    if pairs == [], do: [{to_string(domain), "signal"}], else: pairs
  end

  defp build_pairs(domain, _name, _data), do: [{to_string(domain), "signal"}]

  defp short_val(nil), do: "nil"
  defp short_val(v) when is_binary(v) and byte_size(v) > 24, do: String.slice(v, 0, 22) <> ".."
  defp short_val(v) when is_binary(v), do: v
  defp short_val(v) when is_atom(v), do: Atom.to_string(v)
  defp short_val(v) when is_number(v), do: to_string(v)
  defp short_val(v), do: inspect(v, limit: 3, printable_limit: 20)
end
