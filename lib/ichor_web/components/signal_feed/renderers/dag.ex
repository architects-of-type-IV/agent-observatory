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

  def render(%{message: %Message{name: :dag_status}} = assigns) do
    ~H"""
    <span class="text-[10px] text-muted">pipeline status snapshot</span>
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

  def render(assigns) do
    ~H"""
    <span class="text-[10px] text-muted font-mono">{@message.name}</span>
    """
  end
end
