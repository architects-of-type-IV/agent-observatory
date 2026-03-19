defmodule IchorWeb.Components.MesGenesisComponents do
  @moduledoc """
  Genesis pipeline panel for MES projects.
  Mode A/B/C launch buttons and artifact summary.
  """

  use Phoenix.Component

  alias IchorWeb.Components.MesGateComponents

  @modes [
    %{key: "a", label: "Mode A", desc: "Discover (ADRs)", status: :discover},
    %{key: "b", label: "Mode B", desc: "Define (FRDs/UCs)", status: :define},
    %{key: "c", label: "Mode C", desc: "Build (Roadmap)", status: :build}
  ]

  attr :project, :map, required: true
  attr :genesis_node, :any, default: nil
  attr :gate_report, :any, default: nil

  def genesis_panel(assigns) do
    assigns = assign(assigns, :modes, @modes)

    ~H"""
    <div class="mt-4 pt-3 border-t border-border/50">
      <div class="flex items-center justify-between mb-2">
        <h3 class="text-[9px] font-semibold text-low uppercase tracking-wider">
          Genesis Pipeline
        </h3>
        <div :if={@genesis_node} class="flex items-center gap-1.5">
          <button
            phx-click="mes_gate_check"
            phx-value-node-id={@genesis_node.id}
            class="px-2 py-0.5 text-[9px] font-semibold rounded bg-warning/10 text-warning border border-warning/20 hover:bg-warning/20 transition-colors"
          >
            Gate Check
          </button>
          <button
            phx-click="mes_generate_dag"
            phx-value-node-id={@genesis_node.id}
            class="px-2 py-0.5 text-[9px] font-semibold rounded bg-success/10 text-success border border-success/20 hover:bg-success/20 transition-colors"
          >
            Generate DAG
          </button>
        </div>
      </div>

      <.mode_buttons
        project_id={@project.id}
        genesis_node={@genesis_node}
        modes={@modes}
      />

      <.artifact_summary :if={@genesis_node} genesis_node={@genesis_node} />

      <MesGateComponents.gate_report :if={@gate_report} report={@gate_report} />

      <.node_status :if={@genesis_node} genesis_node={@genesis_node} />
    </div>
    """
  end

  attr :project_id, :string, required: true
  attr :genesis_node, :any, default: nil
  attr :modes, :list, required: true

  defp mode_buttons(assigns) do
    ~H"""
    <div class="flex gap-1.5 mb-3">
      <button
        :for={mode <- @modes}
        phx-click="mes_start_mode"
        phx-value-mode={mode.key}
        phx-value-project-id={@project_id}
        class={[
          "flex-1 px-2 py-1.5 text-[10px] font-semibold rounded border transition-colors text-center",
          mode_button_class(@genesis_node, mode.status)
        ]}
      >
        <div class="font-bold">{mode.label}</div>
        <div class="text-[8px] opacity-70 mt-0.5">{mode.desc}</div>
      </button>
    </div>
    """
  end

  defp mode_button_class(nil, _status) do
    "bg-brand/10 text-brand border-brand/20 hover:bg-brand/20"
  end

  defp mode_button_class(%{status: current}, target) when current == target do
    "bg-brand/20 text-brand border-brand/40 ring-1 ring-brand/30"
  end

  defp mode_button_class(%{status: current}, target) do
    case {status_rank(current), status_rank(target)} do
      {current_rank, target_rank} when current_rank > target_rank ->
        "bg-success/10 text-success border-success/20"

      _ ->
        "bg-surface text-muted border-subtle hover:bg-brand/10 hover:text-brand hover:border-brand/20"
    end
  end

  defp status_rank(:discover), do: 1
  defp status_rank(:define), do: 2
  defp status_rank(:build), do: 3
  defp status_rank(:complete), do: 4

  attr :genesis_node, :map, required: true

  defp artifact_summary(assigns) do
    counts = %{
      adrs: length(Map.get(assigns.genesis_node, :adrs, [])),
      features: length(Map.get(assigns.genesis_node, :features, [])),
      use_cases: length(Map.get(assigns.genesis_node, :use_cases, [])),
      conversations: length(Map.get(assigns.genesis_node, :conversations, [])),
      checkpoints: length(Map.get(assigns.genesis_node, :checkpoints, [])),
      phases: length(Map.get(assigns.genesis_node, :phases, []))
    }

    assigns = assign(assigns, :counts, counts)

    ~H"""
    <div class="grid grid-cols-3 gap-1.5 mb-3">
      <.count_card label="ADRs" count={@counts.adrs} color="brand" />
      <.count_card label="Features" count={@counts.features} color="interactive" />
      <.count_card label="Use Cases" count={@counts.use_cases} color="cyan" />
      <.count_card label="Conversations" count={@counts.conversations} color="violet" />
      <.count_card label="Checkpoints" count={@counts.checkpoints} color="warning" />
      <.count_card label="Phases" count={@counts.phases} color="success" />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :color, :string, required: true

  defp count_card(assigns) do
    assigns = assign(assigns, :classes, count_card_classes(assigns.color))

    ~H"""
    <div class={["px-2 py-1.5 rounded text-center", @classes.bg]}>
      <div class={["text-sm font-bold", @classes.text]}>{@count}</div>
      <div class="text-[8px] text-muted uppercase tracking-wider">{@label}</div>
    </div>
    """
  end

  # Static class strings for Tailwind scanner
  defp count_card_classes("brand"),
    do: %{bg: "bg-brand/5 border border-brand/10", text: "text-brand"}

  defp count_card_classes("interactive"),
    do: %{bg: "bg-interactive/5 border border-interactive/10", text: "text-interactive"}

  defp count_card_classes("cyan"), do: %{bg: "bg-cyan/5 border border-cyan/10", text: "text-cyan"}

  defp count_card_classes("violet"),
    do: %{bg: "bg-violet/5 border border-violet/10", text: "text-violet"}

  defp count_card_classes("warning"),
    do: %{bg: "bg-warning/5 border border-warning/10", text: "text-warning"}

  defp count_card_classes("success"),
    do: %{bg: "bg-success/5 border border-success/10", text: "text-success"}

  attr :genesis_node, :map, required: true

  defp node_status(assigns) do
    ~H"""
    <div class="flex items-center gap-2 text-[10px] text-muted">
      <span class="text-low">Stage:</span>
      <span class="font-semibold text-default uppercase tracking-wider">
        {@genesis_node.status}
      </span>
      <span :if={@genesis_node.title} class="text-low">|</span>
      <span :if={@genesis_node.title} class="text-default truncate">
        {@genesis_node.title}
      </span>
    </div>
    """
  end
end
