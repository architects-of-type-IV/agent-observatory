defmodule IchorWeb.Components.MesFactoryComponents do
  @moduledoc "Factory view components: action bar, tab bar, and station controls."

  use Phoenix.Component
  alias Ichor.Factory.PipelineStage

  attr :project, :map, required: true
  attr :planning_project, :any, required: true
  attr :reader_open, :boolean, default: false

  def action_bar(assigns) do
    {stage, label} = PipelineStage.derive(assigns.planning_project)
    {text_class, bg_class} = PipelineStage.stage_color(stage)
    stations = PipelineStage.station_states(stage)

    assigns =
      assign(assigns,
        stage: stage,
        stage_label: label,
        text_class: text_class,
        bg_class: bg_class,
        stations: stations
      )

    ~H"""
    <div class="px-3 py-2 border-b border-border flex-shrink-0 bg-surface/30">
      <div class="flex items-center gap-2 min-w-0">
        <h2 class="text-[13px] font-bold text-high truncate min-w-0 flex-1">{@project.title}</h2>
        <button
          phx-click="mes_deselect_project"
          class="px-2 py-0.5 text-[9px] font-semibold text-muted bg-surface border border-subtle rounded hover:text-default transition-colors shrink-0"
        >
          Back to list
        </button>
      </div>
      <div class="flex items-center justify-between mt-1.5">
        <span class={[
          "text-[7px] px-1.5 py-0.5 rounded font-bold uppercase tracking-wider",
          @text_class,
          @bg_class
        ]}>
          {@stage_label}
        </span>
        <div class="flex items-center rounded-md overflow-hidden border border-zinc-700/60">
          <.mode_btn label="A" state={@stations.a} mode="a" project_id={@project.id} />
          <.mode_btn label="B" state={@stations.b} mode="b" project_id={@project.id} />
          <.mode_btn label="C" state={@stations.c} mode="c" project_id={@project.id} />
          <span class="w-px h-4 bg-zinc-700" />
          <.station_btn
            label="Gate"
            state={@stations.gate}
            event="mes_gate_check"
            project_id={@planning_project && @planning_project.id}
          />
          <.build_btn
            state={@stations.dag}
            project_id={@project.id}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :state, :atom, required: true
  attr :mode, :string, required: true
  attr :project_id, :string, required: true

  @pill_active "px-2.5 py-1 text-[8px] font-bold bg-brand/15 text-brand hover:bg-brand/25 transition-colors cursor-pointer"
  @pill_completed "px-2.5 py-1 text-[8px] font-bold bg-success/10 text-success/70 hover:bg-success/20 transition-colors cursor-pointer"
  @pill_future "px-2.5 py-1 text-[8px] font-bold text-zinc-600"

  defp mode_btn(%{state: :future} = assigns) do
    assigns = assign(assigns, :cls, @pill_future)
    ~H"<span class={@cls}>{@label}</span>"
  end

  defp mode_btn(%{state: :completed} = assigns) do
    assigns = assign(assigns, :cls, @pill_completed)

    ~H"""
    <button
      phx-click="mes_start_mode"
      phx-value-mode={@mode}
      phx-value-project-id={@project_id}
      class={@cls}
    >
      {@label}
    </button>
    """
  end

  defp mode_btn(assigns) do
    assigns = assign(assigns, :cls, @pill_active)

    ~H"""
    <button
      phx-click="mes_start_mode"
      phx-value-mode={@mode}
      phx-value-project-id={@project_id}
      class={@cls}
    >
      {@label}
    </button>
    """
  end

  attr :label, :string, required: true
  attr :state, :atom, required: true
  attr :event, :string, required: true
  attr :project_id, :any, default: nil

  defp station_btn(%{state: :active} = assigns) do
    assigns = assign(assigns, :cls, @pill_active)

    ~H"""
    <button phx-click={@event} phx-value-project-id={@project_id} class={@cls}>
      {@label}
    </button>
    """
  end

  defp station_btn(%{state: :completed} = assigns) do
    assigns = assign(assigns, :cls, @pill_completed)
    ~H"<span class={@cls}>{@label}</span>"
  end

  defp station_btn(assigns) do
    assigns = assign(assigns, :cls, @pill_future)
    ~H"<span class={@cls}>{@label}</span>"
  end

  @pill_build "px-2.5 py-1 text-[8px] font-bold bg-warning/15 text-warning hover:bg-warning/25 transition-colors cursor-pointer"

  defp build_btn(%{state: :active} = assigns) do
    assigns = assign(assigns, :cls, @pill_build)

    ~H"""
    <button
      phx-click="mes_launch_dag"
      phx-value-project-id={@project_id}
      class={@cls}
    >
      Build
    </button>
    """
  end

  defp build_btn(%{state: :completed} = assigns) do
    assigns = assign(assigns, :cls, @pill_completed)
    ~H"<span class={@cls}>Built</span>"
  end

  defp build_btn(assigns) do
    assigns = assign(assigns, :cls, @pill_future)
    ~H"<span class={@cls}>Build</span>"
  end

  attr :active, :atom, required: true
  attr :planning_project, :any, required: true

  def tab_bar(assigns) do
    node = assigns.planning_project

    counts = %{
      decisions: length(artifacts(node, :adr)),
      requirements: length(artifacts(node, :feature)) + length(artifacts(node, :use_case)),
      checkpoints: length(artifacts(node, :checkpoint)) + length(artifacts(node, :conversation)),
      roadmap: length(roadmap_items(node, :phase))
    }

    assigns = assign(assigns, counts: counts)

    ~H"""
    <div class="flex border-b border-border flex-shrink-0">
      <.tab_btn key={:decisions} label="Decisions" count={@counts.decisions} active={@active} />
      <.tab_btn
        key={:requirements}
        label="Requirements"
        count={@counts.requirements}
        active={@active}
      />
      <.tab_btn key={:checkpoints} label="Checkpoints" count={@counts.checkpoints} active={@active} />
      <.tab_btn key={:roadmap} label="Roadmap" count={@counts.roadmap} active={@active} />
    </div>
    """
  end

  attr :key, :atom, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :active, :atom, required: true

  defp tab_btn(assigns) do
    active = assigns.key == assigns.active

    assigns = assign(assigns, :active, active)

    ~H"""
    <button
      phx-click="planning_switch_tab"
      phx-value-tab={@key}
      class={[
        "px-5 py-2.5 text-[9px] font-bold uppercase tracking-wider border-b-2 transition-colors",
        if(@active,
          do: "text-brand border-brand bg-brand/[0.04]",
          else: "text-muted border-transparent hover:text-default hover:bg-white/[0.02]"
        )
      ]}
    >
      {@label}
      <span class={["ml-1 text-[8px]", if(@active, do: "opacity-60", else: "opacity-50")]}>
        {@count}
      </span>
    </button>
    """
  end

  defp artifacts(nil, _kind), do: []
  defp artifacts(node, kind), do: Enum.filter(Map.get(node, :artifacts, []), &(&1.kind == kind))

  defp roadmap_items(nil, _kind), do: []

  defp roadmap_items(node, kind),
    do: Enum.filter(Map.get(node, :roadmap_items, []), &(&1.kind == kind))
end
