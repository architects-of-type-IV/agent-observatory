defmodule IchorWeb.Components.MesFactoryComponents do
  @moduledoc """
  Factory view components: action bar, description, artifact tabs, and artifact list.
  """

  use Phoenix.Component
  alias Ichor.Genesis.PipelineStage

  # ── Action Bar ───────────────────────────────────────────────────────

  attr :project, :map, required: true
  attr :genesis_node, :any, required: true
  attr :reader_open, :boolean, default: false

  def action_bar(assigns) do
    {stage, label} = PipelineStage.derive(assigns.genesis_node)
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
      <%!-- Row 2: Stage badge (left) + station pill (right) --%>
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
            node_id={@genesis_node && @genesis_node.id}
          />
          <.station_btn
            label="DAG"
            state={@stations.dag}
            event="mes_generate_dag"
            node_id={@genesis_node && @genesis_node.id}
          />
        </div>
      </div>
    </div>
    """
  end

  # Mode buttons emit mes_start_mode with project-id
  attr :label, :string, required: true
  attr :state, :atom, required: true
  attr :mode, :string, required: true
  attr :project_id, :string, required: true

  @pill_active "px-2.5 py-1 text-[8px] font-bold bg-brand/15 text-brand hover:bg-brand/25 transition-colors cursor-pointer"
  @pill_completed "px-2.5 py-1 text-[8px] font-bold bg-success/10 text-success/70"
  @pill_future "px-2.5 py-1 text-[8px] font-bold text-zinc-600"

  defp mode_btn(%{state: :active} = assigns) do
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

  defp mode_btn(%{state: :completed} = assigns) do
    assigns = assign(assigns, :cls, @pill_completed)
    ~H"<span class={@cls}>{@label}</span>"
  end

  defp mode_btn(assigns) do
    assigns = assign(assigns, :cls, @pill_future)
    ~H"<span class={@cls}>{@label}</span>"
  end

  # Station buttons (Gate, DAG) emit their event with node-id
  attr :label, :string, required: true
  attr :state, :atom, required: true
  attr :event, :string, required: true
  attr :node_id, :any, default: nil

  defp station_btn(%{state: :active} = assigns) do
    assigns = assign(assigns, :cls, @pill_active)

    ~H"""
    <button phx-click={@event} phx-value-node-id={@node_id} class={@cls}>
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

  # ── Project Brief ────────────────────────────────────────────────────

  attr :project, :map, required: true

  def project_brief(assigns) do
    features = assigns.project.features || []
    use_cases = assigns.project.use_cases || []

    assigns =
      assign(assigns,
        features: features,
        use_cases: use_cases,
        has_details: features != [] or use_cases != []
      )

    ~H"""
    <div class="px-4 py-3 border-b border-border flex-shrink-0 space-y-1.5">
      <p class="text-[11px] text-muted leading-relaxed">{@project.description}</p>
      <div :if={@has_details} class="flex flex-wrap gap-x-4 gap-y-1 text-[9px]">
        <div :if={@features != []} class="flex items-baseline gap-1">
          <span class="text-zinc-500 font-semibold uppercase tracking-wider">Features</span>
          <span
            :for={f <- @features}
            class="px-1.5 py-0.5 rounded bg-interactive/10 text-interactive font-mono"
          >
            {f}
          </span>
        </div>
        <div :if={@use_cases != []} class="flex items-baseline gap-1">
          <span class="text-zinc-500 font-semibold uppercase tracking-wider">Use Cases</span>
          <span :for={uc <- @use_cases} class="px-1.5 py-0.5 rounded bg-brand/10 text-brand font-mono">
            {uc}
          </span>
        </div>
      </div>
      <div :if={@project.signal_interface} class="text-[9px] text-zinc-500">
        <span class="font-semibold uppercase tracking-wider">Interface</span>
        <span class="text-zinc-400 ml-1">{@project.signal_interface}</span>
      </div>
    </div>
    """
  end

  # ── Tab Bar ──────────────────────────────────────────────────────────

  attr :active, :atom, required: true
  attr :genesis_node, :any, required: true

  def tab_bar(assigns) do
    node = assigns.genesis_node
    adrs = safe_list(node, :adrs)
    features = safe_list(node, :features)
    use_cases = safe_list(node, :use_cases)
    checkpoints = safe_list(node, :checkpoints)
    conversations = safe_list(node, :conversations)
    phases = safe_list(node, :phases)

    counts = %{
      decisions: length(adrs),
      requirements: length(features) + length(use_cases),
      checkpoints: length(checkpoints) + length(conversations),
      roadmap: length(phases)
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

  defp tab_btn(%{key: key, active: key} = assigns) do
    ~H"""
    <button
      phx-click="genesis_switch_tab"
      phx-value-tab={@key}
      class="px-5 py-2.5 text-[9px] font-bold uppercase tracking-wider text-brand border-b-2 border-brand bg-brand/[0.04] transition-colors"
    >
      {@label}<span class="ml-1 text-[8px] opacity-60">{@count}</span>
    </button>
    """
  end

  defp tab_btn(assigns) do
    ~H"""
    <button
      phx-click="genesis_switch_tab"
      phx-value-tab={@key}
      class="px-5 py-2.5 text-[9px] font-bold uppercase tracking-wider text-muted border-b-2 border-transparent hover:text-default hover:bg-white/[0.02] transition-colors"
    >
      {@label}<span class="ml-1 text-[8px] opacity-50">{@count}</span>
    </button>
    """
  end

  # ── Artifact List ────────────────────────────────────────────────────

  attr :genesis_node, :any, required: true
  attr :sub_tab, :atom, required: true
  attr :selected, :any, default: nil

  def artifact_list(assigns) do
    items = build_items(assigns.genesis_node, assigns.sub_tab)
    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="w-full overflow-y-auto">
      <div :if={@items == []} class="px-4 py-10 text-center text-[11px] text-muted">
        No artifacts yet.
      </div>
      <button
        :for={item <- @items}
        phx-click="genesis_select_artifact"
        phx-value-type={item.type}
        phx-value-id={item.id}
        class={[
          "flex items-center gap-2.5 px-3.5 py-2.5 border-b border-subtle w-full text-left text-default transition-colors",
          "hover:bg-white/[0.03]",
          if(selected?(@selected, item.type, item.id), do: "bg-brand/10", else: "bg-transparent")
        ]}
      >
        <span
          :if={item.code != ""}
          class={["font-mono text-[9px] flex-shrink-0 min-w-[50px]", item.code_class]}
        >
          {item.code}
        </span>
        <span class="text-[11px] font-semibold flex-1 truncate">{item.label}</span>
        <span
          :if={item.badge != ""}
          class="text-[8px] px-1.5 py-0.5 rounded font-bold uppercase flex-shrink-0 bg-brand/10 text-brand"
        >
          {item.badge}
        </span>
      </button>
    </div>
    """
  end

  defp selected?({type, id}, type, id), do: true
  defp selected?(_, _, _), do: false

  defp build_items(node, :decisions) do
    node
    |> safe_list(:adrs)
    |> Enum.map(fn adr ->
      %{
        type: :adr,
        id: adr.id,
        code: adr.code,
        code_class: "text-brand",
        label: adr.title,
        badge: to_string(adr.status)
      }
    end)
  end

  defp build_items(node, :requirements) do
    features =
      node
      |> safe_list(:features)
      |> Enum.map(fn f ->
        %{
          type: :feature,
          id: f.id,
          code: f.code,
          code_class: "text-interactive",
          label: f.title,
          badge: ""
        }
      end)

    use_cases =
      node
      |> safe_list(:use_cases)
      |> Enum.map(fn uc ->
        %{
          type: :use_case,
          id: uc.id,
          code: uc.code,
          code_class: "text-interactive",
          label: uc.title,
          badge: ""
        }
      end)

    features ++ use_cases
  end

  defp build_items(node, :checkpoints) do
    checkpoints =
      node
      |> safe_list(:checkpoints)
      |> Enum.map(fn cp ->
        %{
          type: :checkpoint,
          id: cp.id,
          code: "",
          code_class: "",
          label: cp.title,
          badge: to_string(cp.mode)
        }
      end)

    conversations =
      node
      |> safe_list(:conversations)
      |> Enum.map(fn conv ->
        %{
          type: :conversation,
          id: conv.id,
          code: "",
          code_class: "",
          label: conv.title,
          badge: to_string(conv.mode)
        }
      end)

    checkpoints ++ conversations
  end

  defp build_items(node, :roadmap) do
    node
    |> safe_list(:phases)
    |> Enum.map(fn phase ->
      %{
        type: :phase,
        id: phase.id,
        code: "P#{phase.number}",
        code_class: "text-success",
        label: phase.title,
        badge: ""
      }
    end)
  end

  defp build_items(_node, _tab), do: []

  defp safe_list(nil, _key), do: []

  defp safe_list(node, key) do
    case Map.get(node, key, []) do
      list when is_list(list) -> list
      _ -> []
    end
  end
end
