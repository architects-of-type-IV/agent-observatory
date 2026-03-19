defmodule IchorWeb.SignalFeed.Renderers.Mes do
  @moduledoc """
  Renders signals in the :mes domain.
  Covers project lifecycle, scheduler, tmux spawning, quality gates, and research.
  """
  use Phoenix.Component

  alias Ichor.Signals.Message
  alias IchorWeb.SignalFeed.Primitives

  attr :seq, :integer, required: true
  attr :message, :any, required: true

  def render(%{message: %Message{name: :mes_project_created, data: data}} = assigns) do
    assigns =
      assign(assigns,
        title: to_string(data[:title] || "?"),
        project_id: Primitives.short(data[:project_id])
      )

    ~H"""
    <span class="text-[10px] text-high">
      project <span class="font-semibold">{@title}</span> created
    </span>
    <Primitives.kv key="id" value={@project_id} />
    """
  end

  def render(%{message: %Message{name: :mes_project_picked_up, data: data}} = assigns) do
    assigns =
      assign(assigns,
        project_id: Primitives.short(data[:project_id]),
        sid: Primitives.short(data[:session_id])
      )

    ~H"""
    <span class="text-[10px] text-default">project picked up</span>
    <Primitives.kv key="by" value={@sid} />
    <Primitives.kv key="project" value={@project_id} />
    """
  end

  def render(%{message: %Message{name: :mes_project_compiled, data: data}} = assigns) do
    assigns = assign(assigns, title: to_string(data[:title] || "?"))

    ~H"""
    <span class="text-[10px] text-success font-medium">
      project <span class="font-semibold">{@title}</span> compiled
    </span>
    """
  end

  def render(%{message: %Message{name: :mes_project_failed, data: data}} = assigns) do
    assigns = assign(assigns, title: to_string(data[:title] || "?"))

    ~H"""
    <span class="text-[10px] text-error font-medium">
      project <span class="font-semibold">{@title}</span> failed
    </span>
    """
  end

  def render(%{message: %Message{name: :mes_subsystem_loaded, data: data}} = assigns) do
    assigns =
      assign(assigns,
        subsystem: to_string(data[:subsystem] || "?"),
        modules: to_string(length(data[:modules] || []))
      )

    ~H"""
    <span class="text-[10px] text-success">
      subsystem <span class="font-mono">{@subsystem}</span> loaded
    </span>
    <Primitives.kv key="modules" value={@modules} />
    """
  end

  def render(%{message: %Message{name: :mes_subsystem_compile_failed, data: data}} = assigns) do
    assigns = assign(assigns, reason: to_string(data[:reason] || "?"))

    ~H"""
    <span class="text-[10px] text-error font-medium">subsystem compile failed</span>
    <Primitives.kv key="reason" value={@reason} />
    """
  end

  def render(%{message: %Message{name: :mes_cycle_started, data: data}} = assigns) do
    assigns =
      assign(assigns,
        run_id: Primitives.short(data[:run_id]),
        team: to_string(data[:team_name] || "?")
      )

    ~H"""
    <span class="text-[10px] text-default">cycle started</span>
    <Primitives.kv key="team" value={@team} />
    <Primitives.kv key="run" value={@run_id} />
    """
  end

  def render(%{message: %Message{name: :mes_cycle_skipped, data: data}} = assigns) do
    assigns = assign(assigns, active: to_string(data[:active_runs] || "?"))

    ~H"""
    <span class="text-[10px] text-muted">cycle skipped</span>
    <Primitives.kv key="active" value={@active} />
    """
  end

  def render(%{message: %Message{name: :mes_cycle_failed, data: data}} = assigns) do
    assigns = assign(assigns, reason: to_string(data[:reason] || "?"))

    ~H"""
    <span class="text-[10px] text-error">cycle failed</span>
    <Primitives.kv key="reason" value={@reason} />
    """
  end

  def render(%{message: %Message{name: :mes_cycle_timeout, data: data}} = assigns) do
    assigns = assign(assigns, team: to_string(data[:team_name] || "?"))

    ~H"""
    <span class="text-[10px] text-error font-medium">cycle timeout</span>
    <Primitives.kv key="team" value={@team} />
    """
  end

  def render(%{message: %Message{name: :mes_team_ready, data: data}} = assigns) do
    assigns =
      assign(assigns,
        session: to_string(data[:session] || "?"),
        count: to_string(data[:agent_count] || "?")
      )

    ~H"""
    <span class="text-[10px] text-success">team ready</span>
    <Primitives.kv key="agents" value={@count} />
    <Primitives.kv key="session" value={@session} />
    """
  end

  def render(%{message: %Message{name: :mes_team_killed, data: data}} = assigns) do
    assigns = assign(assigns, session: to_string(data[:session] || "?"))

    ~H"""
    <span class="text-[10px] text-medium">team killed</span>
    <Primitives.kv key="session" value={@session} />
    """
  end

  def render(%{message: %Message{name: :mes_quality_gate_passed, data: data}} = assigns) do
    assigns =
      assign(assigns,
        gate: to_string(data[:gate] || "?"),
        run_id: Primitives.short(data[:run_id])
      )

    ~H"""
    <span class="text-[10px] text-success">gate <span class="font-mono">{@gate}</span> passed</span>
    <Primitives.kv key="run" value={@run_id} />
    """
  end

  def render(%{message: %Message{name: :mes_quality_gate_failed, data: data}} = assigns) do
    assigns =
      assign(assigns,
        gate: to_string(data[:gate] || "?"),
        reason: to_string(data[:reason] || "?")
      )

    ~H"""
    <span class="text-[10px] text-error font-medium">
      gate <span class="font-mono">{@gate}</span> failed
    </span>
    <Primitives.kv key="reason" value={@reason} />
    """
  end

  def render(%{message: %Message{name: :mes_quality_gate_escalated, data: data}} = assigns) do
    assigns =
      assign(assigns,
        gate: to_string(data[:gate] || "?"),
        failures: to_string(data[:failure_count] || "?")
      )

    ~H"""
    <span class="text-[10px] text-error font-medium">
      gate <span class="font-mono">{@gate}</span> escalated
    </span>
    <Primitives.kv key="failures" value={@failures} />
    """
  end

  def render(%{message: %Message{name: :mes_research_ingested, data: data}} = assigns) do
    assigns =
      assign(assigns,
        run_id: Primitives.short(data[:run_id]),
        episode_id: Primitives.short(data[:episode_id])
      )

    ~H"""
    <span class="text-[10px] text-success">research ingested</span>
    <Primitives.kv key="run" value={@run_id} />
    <Primitives.kv key="episode" value={@episode_id} />
    """
  end

  def render(%{message: %Message{name: :mes_research_ingest_failed, data: data}} = assigns) do
    assigns = assign(assigns, reason: to_string(data[:reason] || "?"))

    ~H"""
    <span class="text-[10px] text-error">research ingest failed</span>
    <Primitives.kv key="reason" value={@reason} />
    """
  end

  def render(%{message: %Message{name: :mes_dag_generated, data: data}} = assigns) do
    assigns = assign(assigns, node_id: Primitives.short(data[:node_id]))

    ~H"""
    <span class="text-[10px] text-default">DAG generated</span>
    <Primitives.kv key="node" value={@node_id} />
    """
  end

  def render(%{message: %Message{name: :mes_dag_launched, data: data}} = assigns) do
    assigns =
      assign(assigns,
        node_id: Primitives.short(data[:node_id]),
        session: to_string(data[:session] || "?")
      )

    ~H"""
    <span class="text-[10px] text-success">DAG launched</span>
    <Primitives.kv key="node" value={@node_id} />
    <Primitives.kv key="session" value={@session} />
    """
  end

  def render(%{message: %Message{name: name, data: data}} = assigns)
      when name in [:mes_scheduler_init, :mes_scheduler_paused, :mes_scheduler_resumed] do
    assigns = assign(assigns, label: scheduler_label(name), tick: data[:tick])

    ~H"""
    <span class="text-[10px] text-muted">{@label}</span>
    <Primitives.kv :if={@tick} key="tick" value={to_string(@tick)} />
    """
  end

  def render(%{message: %Message{name: :mes_tick, data: data}} = assigns) do
    assigns =
      assign(assigns,
        tick: to_string(data[:tick] || "?"),
        active: to_string(data[:active_runs] || 0)
      )

    ~H"""
    <span class="text-[10px] text-muted">tick {@tick}</span>
    <Primitives.kv key="active" value={@active} />
    """
  end

  def render(%{message: %Message{name: :mes_agent_registered, data: data}} = assigns) do
    assigns = assign(assigns, name: to_string(data[:agent_name] || "?"))

    ~H"""
    <span class="text-[10px] text-default">
      agent <span class="font-mono">{@name}</span> registered
    </span>
    """
  end

  def render(%{message: %Message{name: :mes_agent_stopped, data: data}} = assigns) do
    assigns =
      assign(assigns,
        agent_id: Primitives.short(data[:agent_id]),
        reason: to_string(data[:reason] || "?")
      )

    ~H"""
    <span class="text-[10px] text-medium">
      agent <span class="font-mono">{@agent_id}</span> stopped
    </span>
    <Primitives.kv key="reason" value={@reason} />
    """
  end

  def render(assigns) do
    ~H"""
    <span class="text-[10px] text-muted font-mono">{@message.name}</span>
    """
  end

  defp scheduler_label(:mes_scheduler_init), do: "scheduler init"
  defp scheduler_label(:mes_scheduler_paused), do: "scheduler paused"
  defp scheduler_label(:mes_scheduler_resumed), do: "scheduler resumed"
end
