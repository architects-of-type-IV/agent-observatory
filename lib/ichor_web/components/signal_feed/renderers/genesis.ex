defmodule IchorWeb.SignalFeed.Renderers.Genesis do
  @moduledoc """
  Renders signals in the :genesis domain.
  Covers node creation, advancement, artifact creation, and run lifecycle.
  """
  use Phoenix.Component

  alias Ichor.Signals.Message
  alias IchorWeb.SignalFeed.Primitives

  attr :seq, :integer, required: true
  attr :message, :any, required: true

  def render(%{message: %Message{name: :genesis_node_created, data: data}} = assigns) do
    assigns =
      assign(assigns,
        title: to_string(data[:title] || "?"),
        type: data[:type]
      )

    ~H"""
    <span class="text-[10px] text-high">
      node <span class="font-semibold">{@title}</span> created
    </span>
    <Primitives.kv :if={@type} key="type" value={to_string(@type)} />
    """
  end

  def render(%{message: %Message{name: :genesis_node_advanced, data: data}} = assigns) do
    assigns =
      assign(assigns,
        title: to_string(data[:title] || "?"),
        type: data[:type]
      )

    ~H"""
    <span class="text-[10px] text-high">
      node <span class="font-semibold">{@title}</span> advanced
    </span>
    <Primitives.kv :if={@type} key="type" value={to_string(@type)} />
    """
  end

  def render(%{message: %Message{name: :genesis_artifact_created, data: data}} = assigns) do
    assigns =
      assign(assigns,
        type: to_string(data[:type] || "artifact"),
        node_id: Primitives.short(data[:node_id])
      )

    ~H"""
    <span class="text-[10px] text-high">{@type} created</span>
    <Primitives.kv key="node" value={@node_id} />
    """
  end

  def render(%{message: %Message{name: :genesis_team_ready, data: data}} = assigns) do
    assigns =
      assign(assigns,
        mode: to_string(data[:mode] || "?"),
        count: to_string(data[:agent_count] || "?")
      )

    ~H"""
    <span class="text-[10px] text-success">{@mode} team ready</span>
    <Primitives.kv key="agents" value={@count} />
    """
  end

  def render(%{message: %Message{name: :genesis_team_spawn_failed, data: data}} = assigns) do
    assigns = assign(assigns, reason: to_string(data[:reason] || "?"))

    ~H"""
    <span class="text-[10px] text-error font-medium">team spawn failed</span>
    <Primitives.kv key="reason" value={@reason} />
    """
  end

  def render(%{message: %Message{name: :genesis_team_killed, data: data}} = assigns) do
    assigns = assign(assigns, session: to_string(data[:session] || "?"))

    ~H"""
    <span class="text-[10px] text-medium">team killed</span>
    <Primitives.kv key="session" value={@session} />
    """
  end

  def render(%{message: %Message{name: :genesis_run_init, data: data}} = assigns) do
    assigns =
      assign(assigns,
        run_id: Primitives.short(data[:run_id]),
        mode: to_string(data[:mode] || "?")
      )

    ~H"""
    <span class="text-[10px] text-medium">run init</span>
    <span class="font-mono text-[9px]">{@run_id}</span>
    <Primitives.kv key="mode" value={@mode} />
    """
  end

  def render(%{message: %Message{name: :genesis_run_complete, data: data}} = assigns) do
    assigns =
      assign(assigns,
        run_id: Primitives.short(data[:run_id]),
        mode: to_string(data[:mode] || "?")
      )

    ~H"""
    <span class="text-[10px] text-success font-medium">run complete</span>
    <span class="font-mono text-[9px]">{@run_id}</span>
    <Primitives.kv key="mode" value={@mode} />
    """
  end

  def render(%{message: %Message{name: :genesis_run_terminated, data: data}} = assigns) do
    assigns = assign(assigns, run_id: Primitives.short(data[:run_id]))

    ~H"""
    <span class="text-[10px] text-medium">run terminated</span>
    <span class="font-mono text-[9px]">{@run_id}</span>
    """
  end

  def render(%{message: %Message{name: :genesis_tmux_gone, data: data}} = assigns) do
    assigns = assign(assigns, run_id: Primitives.short(data[:run_id]))

    ~H"""
    <span class="text-[10px] text-muted">tmux gone</span>
    <span class="font-mono text-[9px]">{@run_id}</span>
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
