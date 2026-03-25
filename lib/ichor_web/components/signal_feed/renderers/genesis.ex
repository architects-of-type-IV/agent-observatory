defmodule IchorWeb.SignalFeed.Renderers.Genesis do
  @moduledoc """
  Renders signals in the planning topic namespace.
  Covers project and run lifecycle signals.
  """
  use Phoenix.Component

  alias Ichor.Events.Event
  alias IchorWeb.SignalFeed.Primitives

  attr :seq, :integer, required: true
  attr :event, :any, required: true

  def render(%{event: %Event{topic: "planning.project.created", data: data}} = assigns) do
    assigns =
      assign(assigns,
        title: to_string(data[:title] || "?"),
        type: data[:type]
      )

    ~H"""
    <span class="text-[10px] text-high">
      project <span class="font-semibold">{@title}</span> created
    </span>
    <Primitives.kv :if={@type} key="type" value={to_string(@type)} />
    """
  end

  def render(%{event: %Event{topic: "planning.project.advanced", data: data}} = assigns) do
    assigns =
      assign(assigns,
        title: to_string(data[:title] || "?"),
        type: data[:type]
      )

    ~H"""
    <span class="text-[10px] text-high">
      project <span class="font-semibold">{@title}</span> advanced
    </span>
    <Primitives.kv :if={@type} key="type" value={to_string(@type)} />
    """
  end

  def render(%{event: %Event{topic: "planning.project.artifact_created", data: data}} = assigns) do
    assigns =
      assign(assigns,
        type: to_string(data[:type] || "artifact"),
        project_id: Primitives.short(data[:project_id])
      )

    ~H"""
    <span class="text-[10px] text-high">{@type} created</span>
    <Primitives.kv key="project" value={@project_id} />
    """
  end

  def render(%{event: %Event{topic: "planning.team.ready", data: data}} = assigns) do
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

  def render(%{event: %Event{topic: "planning.team.spawn_failed", data: data}} = assigns) do
    assigns = assign(assigns, reason: to_string(data[:reason] || "?"))

    ~H"""
    <span class="text-[10px] text-error font-medium">team spawn failed</span>
    <Primitives.kv key="reason" value={@reason} />
    """
  end

  def render(%{event: %Event{topic: "planning.team.killed", data: data}} = assigns) do
    assigns = assign(assigns, session: to_string(data[:session] || "?"))

    ~H"""
    <span class="text-[10px] text-medium">team killed</span>
    <Primitives.kv key="session" value={@session} />
    """
  end

  def render(%{event: %Event{topic: "planning.run.init", data: data}} = assigns) do
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

  def render(%{event: %Event{topic: "planning.run.complete", data: data}} = assigns) do
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

  def render(%{event: %Event{topic: "planning.run.terminated", data: data}} = assigns) do
    assigns = assign(assigns, run_id: Primitives.short(data[:run_id]))

    ~H"""
    <span class="text-[10px] text-medium">run terminated</span>
    <span class="font-mono text-[9px]">{@run_id}</span>
    """
  end

  def render(%{event: %Event{topic: "planning.tmux_gone", data: data}} = assigns) do
    assigns = assign(assigns, run_id: Primitives.short(data[:run_id]))

    ~H"""
    <span class="text-[10px] text-muted">tmux gone</span>
    <span class="font-mono text-[9px]">{@run_id}</span>
    """
  end

  def render(%{event: %Event{topic: topic, data: data}} = assigns) do
    assigns =
      assign(assigns,
        topic: topic,
        pairs: Primitives.data_to_pairs(data)
      )

    ~H"""
    <span class="text-[10px] text-muted font-mono mr-1">{@topic}</span>
    <span :for={p <- @pairs} class="mr-1">
      <Primitives.kv key={p.key} value={p.val} />
    </span>
    """
  end
end
