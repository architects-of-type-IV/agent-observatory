defmodule IchorWeb.Components.MesDetailComponents do
  @moduledoc """
  Detail panel for MES project inspection.
  """

  use Phoenix.Component

  alias IchorWeb.Components.MesGenesisComponents
  alias IchorWeb.Components.MesStatusComponents

  attr :project, :map, required: true
  attr :genesis_node, :any, default: nil
  attr :gate_report, :any, default: nil

  def project_detail(assigns) do
    ~H"""
    <div class="p-4">
      <%!-- Title + badge + action --%>
      <div class="flex items-start justify-between gap-3 mb-1">
        <h2 class="text-base font-bold text-high tracking-tight leading-tight">
          {@project.title}
        </h2>
        <div class="flex items-center gap-2 shrink-0">
          <MesStatusComponents.status_badge status={@project.status} />
          <MesStatusComponents.action_button project={@project} />
        </div>
      </div>

      <p class="font-mono text-[10px] text-brand mb-3">{@project.subsystem}</p>

      <p class="text-[11px] text-default leading-relaxed mb-4">{@project.description}</p>

      <%!-- Features --%>
      <.detail_section
        :if={@project.features != [] && @project.features != nil}
        label="Features"
      >
        <.tag_list items={@project.features} color="interactive" />
      </.detail_section>

      <%!-- Use Cases --%>
      <.detail_section
        :if={@project.use_cases != [] && @project.use_cases != nil}
        label="Use Cases"
      >
        <.tag_list items={@project.use_cases} color="cyan" />
      </.detail_section>

      <%!-- Signals Emitted --%>
      <.detail_section
        :if={@project.signals_emitted != [] && @project.signals_emitted != nil}
        label="Signals Emitted"
      >
        <.tag_list items={@project.signals_emitted} color="brand" mono />
      </.detail_section>

      <%!-- Signals Subscribed --%>
      <.detail_section
        :if={@project.signals_subscribed != [] && @project.signals_subscribed != nil}
        label="Signals Subscribed"
      >
        <.tag_list items={@project.signals_subscribed} color="cyan" mono />
      </.detail_section>

      <%!-- Architecture --%>
      <.detail_section
        :if={@project.architecture && @project.architecture != ""}
        label="Architecture"
      >
        <.mono_block text={@project.architecture} />
      </.detail_section>

      <%!-- Dependencies --%>
      <.detail_section
        :if={@project.dependencies != [] && @project.dependencies != nil}
        label="Dependencies"
      >
        <.tag_list items={@project.dependencies} color="violet" mono />
      </.detail_section>

      <%!-- Build Log --%>
      <.detail_section
        :if={@project.build_log && @project.status == :failed}
        label="Build Log"
      >
        <div class="font-mono text-[10px] text-error p-2.5 rounded bg-error/5 border border-error/15 whitespace-pre-wrap max-h-40 overflow-auto">
          {@project.build_log}
        </div>
      </.detail_section>

      <%!-- Genesis Pipeline --%>
      <MesGenesisComponents.genesis_panel
        project={@project}
        genesis_node={@genesis_node}
        gate_report={@gate_report}
      />

      <%!-- Footer metadata --%>
      <div class="mt-4 pt-3 border-t border-border/50 flex flex-wrap gap-x-4 gap-y-1 text-[10px] text-muted">
        <span :if={@project.version}>
          <span class="text-low">v</span><span class="font-mono text-default">{@project.version}</span>
        </span>
        <span :if={@project.topic}>
          <span class="font-mono text-default">{@project.topic}</span>
        </span>
        <span :if={@project.team_name}>
          Team: <span class="text-default">{@project.team_name}</span>
        </span>
        <span :if={@project.signal_interface}>
          Interface: <span class="text-default">{@project.signal_interface}</span>
        </span>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  def detail_section(assigns) do
    ~H"""
    <div class="mb-3">
      <h4 class="text-[9px] font-semibold text-low uppercase tracking-wider mb-1.5">{@label}</h4>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :items, :list, required: true
  attr :color, :string, required: true
  attr :mono, :boolean, default: false

  def tag_list(assigns) do
    assigns = assign(assigns, :tag_classes, tag_classes(assigns.color))

    ~H"""
    <div class="flex flex-wrap gap-1">
      <span
        :for={item <- @items}
        class={[
          "text-[9px] px-1.5 py-0.5 rounded",
          @tag_classes,
          @mono && "font-mono"
        ]}
      >
        {item}
      </span>
    </div>
    """
  end

  # Static class strings for Tailwind scanner
  defp tag_classes("interactive"),
    do: "bg-interactive/10 text-interactive border border-interactive/15"

  defp tag_classes("cyan"), do: "bg-cyan/10 text-cyan border border-cyan/15"
  defp tag_classes("brand"), do: "bg-brand/10 text-brand border border-brand/15"
  defp tag_classes("violet"), do: "bg-violet/10 text-violet border border-violet/15"
  defp tag_classes("success"), do: "bg-success/10 text-success border border-success/15"
  defp tag_classes(color), do: "bg-#{color}/10 text-#{color} border border-#{color}/15"

  attr :text, :string, required: true

  def mono_block(assigns) do
    ~H"""
    <div class="font-mono text-[10px] text-default p-2.5 rounded bg-surface border border-subtle whitespace-pre-wrap leading-relaxed">
      {@text}
    </div>
    """
  end
end
