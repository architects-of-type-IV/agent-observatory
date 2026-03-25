defmodule IchorWeb.SignalFeed.Primitives do
  @moduledoc """
  Shared micro-components for signal row rendering.
  All components are compact single-line output suitable for dense feed rows.
  """
  use Phoenix.Component

  @doc "Renders a key=value badge in monospace."
  attr :key, :string, required: true
  attr :value, :string, required: true

  def kv(assigns) do
    ~H"""
    <span class="font-mono text-[9px] bg-surface-raised text-medium px-1 rounded">
      {@key}: {@value}
    </span>
    """
  end

  @doc "Renders a colored label chip."
  attr :text, :string, required: true
  attr :class, :string, default: "text-muted"

  def label(assigns) do
    ~H"""
    <span class={"text-[9px] font-medium px-1 rounded bg-raised #{@class}"}>
      {@text}
    </span>
    """
  end

  @doc "Formats a monotonic millisecond timestamp as HH:MM:SS."
  attr :ms, :integer, required: true

  def ts(assigns) do
    ~H"""
    <span class="font-mono text-[9px] text-muted">{format_ms(@ms)}</span>
    """
  end

  @doc "Truncates a binary ID or session string to its first 8 characters."
  attr :id, :any, required: true

  def id_short(assigns) do
    ~H"""
    <span class="font-mono text-[9px]">{short(@id)}</span>
    """
  end

  @doc false
  def data_to_pairs(nil), do: []

  def data_to_pairs(data) when is_map(data) do
    data
    |> Enum.map(fn {k, v} -> %{key: to_string(k), val: format_val(v)} end)
    |> Enum.sort_by(& &1.key)
  end

  def data_to_pairs(_), do: []

  @doc false
  def format_val(nil), do: "nil"
  def format_val(v) when is_binary(v) and byte_size(v) > 60, do: String.slice(v, 0, 57) <> "..."
  def format_val(v) when is_binary(v), do: v
  def format_val(v) when is_atom(v), do: Atom.to_string(v)
  def format_val(v) when is_number(v), do: to_string(v)
  def format_val(v) when is_list(v), do: "[#{length(v)} items]"

  def format_val(v) when is_map(v),
    do: inspect(v, limit: 3, pretty: false) |> String.slice(0, 60)

  def format_val(v), do: inspect(v, limit: 3, printable_limit: 20) |> String.slice(0, 60)

  @doc false
  def truncate(s, max) when byte_size(s) > max, do: String.slice(s, 0, max - 2) <> ".."
  def truncate(s, _max), do: s

  @doc false
  def short(nil), do: "?"
  def short(id) when is_binary(id) and byte_size(id) > 8, do: String.slice(id, 0, 8)
  def short(id) when is_binary(id), do: id
  def short(id) when is_atom(id), do: Atom.to_string(id)
  def short(id), do: inspect(id)

  @doc false
  def format_ms(nil), do: "--:--:--"

  def format_ms(ms) when is_integer(ms) do
    total_seconds = div(ms, 1000)
    h = div(total_seconds, 3600) |> rem(24)
    m = div(total_seconds, 60) |> rem(60)
    s = rem(total_seconds, 60)
    :io_lib.format("~2..0B:~2..0B:~2..0B", [h, m, s]) |> IO.iodata_to_binary()
  end
end
