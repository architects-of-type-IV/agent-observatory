defmodule IchorWeb.Components.MesDetailComponents do
  @moduledoc """
  Metadata sidebar for the MES unified factory view.
  Shows compact project metadata on the right side of the layout.
  """

  use Phoenix.Component

  attr :project, :map, required: true

  def metadata_sidebar(assigns) do
    features = assigns.project.features || []
    use_cases = assigns.project.use_cases || []

    assigns = assign(assigns, features: features, use_cases: use_cases)

    ~H"""
    <div class="w-[220px] shrink-0 border-l border-border overflow-y-auto bg-zinc-900/30 p-3">
      <%!-- Project Brief --%>
      <div class="mb-4 pb-3 border-b border-border/50">
        <h3 class="text-[10px] font-bold text-zinc-300 leading-tight mb-1">{@project.title}</h3>
        <p class="text-[9px] font-mono text-brand mb-2">{@project.subsystem}</p>
        <p class="text-[9px] text-zinc-400 leading-relaxed">{@project.description}</p>
      </div>

      <%!-- Features (what it does) --%>
      <.meta_section :if={@features != []} label="Features">
        <ul class="space-y-0.5">
          <li
            :for={f <- @features}
            class="text-[9px] text-zinc-400 leading-snug pl-2 border-l border-zinc-700"
          >
            {f}
          </li>
        </ul>
      </.meta_section>

      <%!-- Use Cases (what it solves) --%>
      <.meta_section :if={@use_cases != []} label="Use Cases">
        <ul class="space-y-0.5">
          <li
            :for={uc <- @use_cases}
            class="text-[9px] text-zinc-400 leading-snug pl-2 border-l border-brand/30"
          >
            {uc}
          </li>
        </ul>
      </.meta_section>

      <%!-- Signals --%>
      <.meta_section :if={(@project.signals_emitted || []) != []} label="Signals Emitted">
        <.tag_list items={@project.signals_emitted} />
      </.meta_section>

      <.meta_section :if={(@project.signals_subscribed || []) != []} label="Signals Subscribed">
        <.tag_list items={@project.signals_subscribed} />
      </.meta_section>

      <%!-- Architecture --%>
      <.meta_section :if={@project.architecture} label="Architecture">
        <.mono_block text={@project.architecture} />
      </.meta_section>

      <%!-- Dependencies --%>
      <.meta_section :if={(@project.dependencies || []) != []} label="Dependencies">
        <.tag_list items={@project.dependencies} />
      </.meta_section>

      <%!-- Footer --%>
      <div class="mt-4 pt-3 border-t border-border/50 space-y-1 text-[9px] text-muted">
        <div :if={@project.version}>
          v<span class="font-mono text-default">{@project.version}</span>
        </div>
        <div :if={@project.topic}><span class="font-mono text-default">{@project.topic}</span></div>
        <div :if={@project.signal_interface}>
          Interface: <span class="text-default">{@project.signal_interface}</span>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp meta_section(assigns) do
    ~H"""
    <div class="mb-3">
      <h4 class="text-[8px] font-bold text-zinc-500 uppercase tracking-wider mb-1.5">{@label}</h4>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :items, :list, required: true

  def tag_list(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-1">
      <span
        :for={item <- @items}
        class="text-[8px] px-1.5 py-0.5 rounded bg-zinc-800 text-zinc-400 font-mono"
      >
        {item}
      </span>
    </div>
    """
  end

  attr :text, :string, required: true

  def mono_block(assigns) do
    ~H"""
    <div class="text-[9px] font-mono text-zinc-400 p-2 rounded bg-zinc-900 border border-zinc-800 whitespace-pre-wrap leading-relaxed">
      {@text}
    </div>
    """
  end
end
