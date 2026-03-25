defmodule IchorWeb.SignalFeed.Renderers.Hitl do
  @moduledoc """
  Renders signals in the :hitl domain.
  """
  use Phoenix.Component

  alias Ichor.Signals.Message
  alias IchorWeb.SignalFeed.Primitives

  attr :seq, :integer, required: true
  attr :message, :any, required: true

  def render(%{message: %Message{name: :gate_open, data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-error">gate opened</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    """
  end

  def render(%{message: %Message{name: :gate_close, data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-success">gate closed</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    """
  end

  def render(%{message: %Message{name: :hitl_auto_released, data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-medium">auto-released</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    """
  end

  def render(%{message: %Message{name: :hitl_operator_approved, data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-success font-medium">approved</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    """
  end

  def render(%{message: %Message{name: :hitl_operator_rejected, data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-error font-medium">rejected</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    """
  end

  def render(%{message: %Message{data: data}} = assigns) do
    assigns = assign(assigns, :pairs, data_to_pairs(data))

    ~H"""
    <span class="text-[10px] text-muted font-mono mr-1">{@message.name}</span>
    <span :for={p <- @pairs} class="mr-1">
      <Primitives.kv key={p.key} value={p.val} />
    </span>
    """
  end

  defp data_to_pairs(nil), do: []

  defp data_to_pairs(data) when is_map(data) do
    data
    |> Enum.map(fn {k, v} -> %{key: to_string(k), val: format_val(v)} end)
    |> Enum.sort_by(& &1.key)
  end

  defp data_to_pairs(_), do: []

  defp format_val(nil), do: "nil"
  defp format_val(v) when is_binary(v) and byte_size(v) > 60, do: String.slice(v, 0, 57) <> "..."
  defp format_val(v) when is_binary(v), do: v
  defp format_val(v) when is_atom(v), do: Atom.to_string(v)
  defp format_val(v) when is_number(v), do: to_string(v)
  defp format_val(v) when is_list(v), do: "[#{length(v)} items]"

  defp format_val(v) when is_map(v),
    do: inspect(v, limit: 3, pretty: false) |> String.slice(0, 60)

  defp format_val(v), do: inspect(v, limit: 3, printable_limit: 20) |> String.slice(0, 60)
end
