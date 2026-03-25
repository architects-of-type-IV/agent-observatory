defmodule IchorWeb.SignalFeed.Renderers.Mes do
  @moduledoc """
  Renders signals in the :mes domain.
  Covers project lifecycle, scheduler, tmux spawning, quality gates, and research.
  """
  use Phoenix.Component

  alias Ichor.Events.Message
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

  def render(%{message: %Message{name: :mes_plugin_loaded, data: data}} = assigns) do
    assigns =
      assign(assigns,
        plugin: to_string(data[:plugin] || "?"),
        modules: to_string(length(data[:modules] || []))
      )

    ~H"""
    <span class="text-[10px] text-success">
      plugin <span class="font-mono">{@plugin}</span> loaded
    </span>
    <Primitives.kv key="modules" value={@modules} />
    """
  end

  def render(%{message: %Message{name: :mes_plugin_compile_failed, data: data}} = assigns) do
    assigns = assign(assigns, reason: to_string(data[:reason] || "?"))

    ~H"""
    <span class="text-[10px] text-error font-medium">plugin compile failed</span>
    <Primitives.kv key="reason" value={@reason} />
    """
  end

  def render(%{message: %Message{name: :mes_output_unhandled, data: data}} = assigns) do
    assigns =
      assign(assigns,
        output_kind: to_string(data[:output_kind] || "?"),
        project_id: Primitives.short(data[:project_id])
      )

    ~H"""
    <span class="text-[10px] text-warning font-medium">output handler missing</span>
    <Primitives.kv key="kind" value={@output_kind} />
    <Primitives.kv key="project" value={@project_id} />
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

  def render(%{message: %Message{name: :mes_pipeline_generated, data: data}} = assigns) do
    assigns = assign(assigns, project_id: Primitives.short(data[:project_id]))

    ~H"""
    <span class="text-[10px] text-default">Pipeline generated</span>
    <Primitives.kv key="project" value={@project_id} />
    """
  end

  def render(%{message: %Message{name: :mes_pipeline_launched, data: data}} = assigns) do
    assigns =
      assign(assigns,
        project_id: Primitives.short(data[:project_id]),
        session: to_string(data[:session] || "?")
      )

    ~H"""
    <span class="text-[10px] text-success">Pipeline launched</span>
    <Primitives.kv key="project" value={@project_id} />
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

  def render(%{message: %Message{name: :agent_tmux_gone, data: data}} = assigns) do
    assigns = assign(assigns, agent_id: Primitives.short(data[:agent_id]))

    ~H"""
    <span class="text-[10px] text-muted">agent tmux gone</span>
    <span class="font-mono text-[9px]">{@agent_id}</span>
    """
  end

  def render(%{message: %Message{name: :mes_agent_register_failed, data: data}} = assigns) do
    assigns =
      assign(assigns,
        name: to_string(data[:agent_name] || "?"),
        reason: to_string(data[:reason] || "?")
      )

    ~H"""
    <span class="text-[10px] text-error font-medium">agent register failed</span>
    <Primitives.kv key="agent" value={@name} />
    <Primitives.kv key="reason" value={@reason} />
    """
  end

  def render(%{message: %Message{name: :mes_run_init, data: data}} = assigns) do
    assigns =
      assign(assigns,
        run_id: Primitives.short(data[:run_id]),
        team: to_string(data[:team_name] || "?")
      )

    ~H"""
    <span class="text-[10px] text-muted">run init</span>
    <Primitives.kv key="team" value={@team} />
    <Primitives.kv key="run" value={@run_id} />
    """
  end

  def render(%{message: %Message{name: :mes_run_started, data: data}} = assigns) do
    assigns =
      assign(assigns,
        run_id: Primitives.short(data[:run_id]),
        session: to_string(data[:session] || "?")
      )

    ~H"""
    <span class="text-[10px] text-default">run started</span>
    <Primitives.kv key="session" value={@session} />
    <Primitives.kv key="run" value={@run_id} />
    """
  end

  def render(%{message: %Message{name: :mes_run_terminated, data: data}} = assigns) do
    assigns = assign(assigns, run_id: Primitives.short(data[:run_id]))

    ~H"""
    <span class="text-[10px] text-medium">run terminated</span>
    <span class="font-mono text-[9px]">{@run_id}</span>
    """
  end

  def render(%{message: %Message{name: :mes_maintenance_init, data: data}} = assigns) do
    assigns = assign(assigns, monitored: to_string(data[:monitored] || 0))

    ~H"""
    <span class="text-[10px] text-muted">maintenance init</span>
    <Primitives.kv key="monitoring" value={@monitored} />
    """
  end

  def render(%{message: %Message{name: :mes_maintenance_cleaned, data: data}} = assigns) do
    assigns =
      assign(assigns,
        run_id: Primitives.short(data[:run_id]),
        trigger: to_string(data[:trigger] || "?")
      )

    ~H"""
    <span class="text-[10px] text-muted">maintenance cleaned</span>
    <Primitives.kv key="run" value={@run_id} />
    <Primitives.kv key="trigger" value={@trigger} />
    """
  end

  def render(%{message: %Message{name: :mes_maintenance_error, data: data}} = assigns) do
    assigns =
      assign(assigns,
        run_id: Primitives.short(data[:run_id]),
        reason: to_string(data[:reason] || "?")
      )

    ~H"""
    <span class="text-[10px] text-error">maintenance error</span>
    <Primitives.kv key="run" value={@run_id} />
    <Primitives.kv key="reason" value={@reason} />
    """
  end

  def render(%{message: %Message{name: :mes_prompts_written, data: data}} = assigns) do
    assigns =
      assign(assigns,
        run_id: Primitives.short(data[:run_id]),
        count: to_string(data[:agent_count] || "?")
      )

    ~H"""
    <span class="text-[10px] text-default">prompts written</span>
    <Primitives.kv key="agents" value={@count} />
    <Primitives.kv key="run" value={@run_id} />
    """
  end

  def render(%{message: %Message{name: :mes_tmux_spawning, data: data}} = assigns) do
    assigns =
      assign(assigns,
        session: to_string(data[:session] || "?"),
        name: to_string(data[:agent_name] || "?")
      )

    ~H"""
    <span class="text-[10px] text-muted">spawning tmux</span>
    <Primitives.kv key="session" value={@session} />
    <Primitives.kv key="agent" value={@name} />
    """
  end

  def render(%{message: %Message{name: :mes_tmux_session_created, data: data}} = assigns) do
    assigns =
      assign(assigns,
        session: to_string(data[:session] || "?"),
        name: to_string(data[:agent_name] || "?")
      )

    ~H"""
    <span class="text-[10px] text-success">tmux session created</span>
    <Primitives.kv key="session" value={@session} />
    <Primitives.kv key="agent" value={@name} />
    """
  end

  def render(%{message: %Message{name: :mes_tmux_spawn_failed, data: data}} = assigns) do
    assigns =
      assign(assigns,
        session: to_string(data[:session] || "?"),
        exit_code: to_string(data[:exit_code] || "?")
      )

    ~H"""
    <span class="text-[10px] text-error font-medium">tmux spawn failed</span>
    <Primitives.kv key="session" value={@session} />
    <Primitives.kv key="exit" value={@exit_code} />
    """
  end

  def render(%{message: %Message{name: :mes_tmux_window_created, data: data}} = assigns) do
    assigns =
      assign(assigns,
        session: to_string(data[:session] || "?"),
        name: to_string(data[:agent_name] || "?")
      )

    ~H"""
    <span class="text-[10px] text-default">tmux window created</span>
    <Primitives.kv key="agent" value={@name} />
    """
  end

  def render(%{message: %Message{name: :mes_team_spawn_failed, data: data}} = assigns) do
    assigns =
      assign(assigns,
        session: to_string(data[:session] || "?"),
        reason: to_string(data[:reason] || "?")
      )

    ~H"""
    <span class="text-[10px] text-error font-medium">team spawn failed</span>
    <Primitives.kv key="session" value={@session} />
    <Primitives.kv key="reason" value={@reason} />
    """
  end

  def render(%{message: %Message{name: :mes_operator_ensured, data: data}} = assigns) do
    assigns = assign(assigns, status: to_string(data[:status] || "?"))

    ~H"""
    <span class="text-[10px] text-muted">operator ensured</span>
    <Primitives.kv key="status" value={@status} />
    """
  end

  def render(%{message: %Message{name: :mes_cleanup, data: data}} = assigns) do
    assigns = assign(assigns, target: to_string(data[:target] || "?"))

    ~H"""
    <span class="text-[10px] text-muted">cleanup</span>
    <Primitives.kv key="target" value={@target} />
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

  defp scheduler_label(:mes_scheduler_init), do: "scheduler init"
  defp scheduler_label(:mes_scheduler_paused), do: "scheduler paused"
  defp scheduler_label(:mes_scheduler_resumed), do: "scheduler resumed"
end
