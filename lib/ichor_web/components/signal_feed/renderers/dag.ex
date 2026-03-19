defmodule IchorWeb.SignalFeed.Renderers.Dag do
  @moduledoc """
  Renders signals in the :dag domain.
  Covers run lifecycle and job state transitions.
  """
  use Phoenix.Component

  alias Ichor.Signals.Message
  alias IchorWeb.SignalFeed.Primitives

  attr :seq, :integer, required: true
  attr :message, :any, required: true

  def render(%{message: %Message{name: :dag_run_created, data: data}} = assigns) do
    assigns =
      assign(assigns,
        run_id: Primitives.short(data[:run_id]),
        label: to_string(data[:label] || "?"),
        count: to_string(data[:job_count] || "?")
      )

    ~H"""
    <span class="text-[10px] text-high">run <span class="font-semibold">{@label}</span> created</span>
    <Primitives.kv key="jobs" value={@count} />
    <Primitives.kv key="id" value={@run_id} />
    """
  end

  def render(%{message: %Message{name: :dag_run_ready, data: data}} = assigns) do
    assigns =
      assign(assigns,
        run_id: Primitives.short(data[:run_id]),
        session: to_string(data[:session] || "?")
      )

    ~H"""
    <span class="text-[10px] text-success">run ready</span>
    <span class="font-mono text-[9px]">{@run_id}</span>
    <Primitives.kv key="session" value={@session} />
    """
  end

  def render(%{message: %Message{name: :dag_run_completed, data: data}} = assigns) do
    assigns =
      assign(assigns,
        run_id: Primitives.short(data[:run_id]),
        label: to_string(data[:label] || "?")
      )

    ~H"""
    <span class="text-[10px] text-success font-medium">
      run <span class="font-semibold">{@label}</span> completed
    </span>
    <Primitives.kv key="id" value={@run_id} />
    """
  end

  def render(%{message: %Message{name: :dag_run_archived, data: data}} = assigns) do
    assigns =
      assign(assigns,
        run_id: Primitives.short(data[:run_id]),
        label: to_string(data[:label] || "?"),
        reason: to_string(data[:reason] || "?")
      )

    ~H"""
    <span class="text-[10px] text-medium">
      run <span class="font-semibold">{@label}</span> archived
    </span>
    <Primitives.kv key="reason" value={@reason} />
    """
  end

  def render(%{message: %Message{name: :dag_job_claimed, data: data}} = assigns) do
    assigns =
      assign(assigns,
        ext_id: to_string(data[:external_id] || "?"),
        owner: Primitives.short(data[:owner]),
        wave: data[:wave]
      )

    ~H"""
    <span class="text-[10px] text-default">job <span class="font-mono">{@ext_id}</span> claimed</span>
    <Primitives.kv key="by" value={@owner} />
    <Primitives.kv :if={@wave} key="wave" value={to_string(@wave)} />
    """
  end

  def render(%{message: %Message{name: :dag_job_completed, data: data}} = assigns) do
    assigns =
      assign(assigns,
        ext_id: to_string(data[:external_id] || "?"),
        owner: Primitives.short(data[:owner])
      )

    ~H"""
    <span class="text-[10px] text-success">job <span class="font-mono">{@ext_id}</span> done</span>
    <Primitives.kv key="by" value={@owner} />
    """
  end

  def render(%{message: %Message{name: :dag_job_failed, data: data}} = assigns) do
    assigns =
      assign(assigns,
        ext_id: to_string(data[:external_id] || "?"),
        notes: data[:notes]
      )

    ~H"""
    <span class="text-[10px] text-error font-medium">
      job <span class="font-mono">{@ext_id}</span> failed
    </span>
    <Primitives.kv :if={@notes} key="notes" value={to_string(@notes)} />
    """
  end

  def render(%{message: %Message{name: :dag_job_reset, data: data}} = assigns) do
    assigns = assign(assigns, ext_id: to_string(data[:external_id] || "?"))

    ~H"""
    <span class="text-[10px] text-medium">job <span class="font-mono">{@ext_id}</span> reset</span>
    """
  end

  def render(%{message: %Message{name: :dag_status, data: data}} = assigns) do
    assigns = assign(assigns, :status, extract_status(data[:state_map] || %{}))

    ~H"""
    <span class="text-[10px] text-muted">pipeline</span>
    <Primitives.kv key="pending" value={@status.pending} />
    <Primitives.kv key="active" value={@status.in_progress} />
    <Primitives.kv key="done" value={@status.completed} />
    <Primitives.kv :if={@status.failed != "0"} key="failed" value={@status.failed} />
    <Primitives.kv key="archived" value={@status.archive_count} />
    <Primitives.kv :if={@status.ts} key="at" value={@status.ts} />
    """
  end

  def render(%{message: %Message{name: :dag_tmux_gone, data: data}} = assigns) do
    assigns = assign(assigns, run_id: Primitives.short(data[:run_id]))

    ~H"""
    <span class="text-[10px] text-muted">tmux gone</span>
    <span class="font-mono text-[9px]">{@run_id}</span>
    """
  end

  def render(%{message: %Message{name: :dag_health_report, data: data}} = assigns) do
    assigns =
      assign(assigns,
        run_id: Primitives.short(data[:run_id]),
        healthy: data[:healthy],
        issues: to_string(data[:issue_count] || 0)
      )

    ~H"""
    <span class="text-[10px] text-muted">health report</span>
    <span class="font-mono text-[9px]">{@run_id}</span>
    <Primitives.kv :if={!@healthy} key="issues" value={@issues} />
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

  defp extract_status(state_map) do
    pipeline = Map.get(state_map, :pipeline, %{})
    health = Map.get(state_map, :health, %{})
    archives = Map.get(state_map, :archives, [])

    %{
      pending: to_string(Map.get(pipeline, :pending, 0)),
      in_progress: to_string(Map.get(pipeline, :in_progress, 0)),
      completed: to_string(Map.get(pipeline, :completed, 0)),
      failed: to_string(Map.get(pipeline, :failed, 0)),
      archive_count: to_string(length(archives)),
      ts: format_health_ts(Map.get(health, :timestamp))
    }
  end

  defp format_health_ts(nil), do: nil
  defp format_health_ts(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  defp format_health_ts(_), do: nil
end
