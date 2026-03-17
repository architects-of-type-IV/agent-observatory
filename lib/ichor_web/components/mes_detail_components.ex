defmodule IchorWeb.Components.MesDetailComponents do
  @moduledoc """
  Metadata sidebar for the MES unified factory view.
  Shows compact project metadata on the right side of the layout.
  """

  use Phoenix.Component

  attr :project, :map, required: true

  def metadata_sidebar(assigns) do
    ~H"""
    <div class="w-[200px] shrink-0 border-l border-border overflow-y-auto bg-zinc-900/30 p-3">
      <.meta_section label="Pipeline">
        <.meta_row key="ADRs" value={artifact_count(@project, :adrs)} />
        <.meta_row key="FRDs" value={artifact_count(@project, :features)} />
        <.meta_row key="Use Cases" value={artifact_count(@project, :use_cases)} />
        <.meta_row key="Phases" value={artifact_count(@project, :phases)} />
      </.meta_section>

      <.meta_section :if={(@project.signals_emitted || []) != []} label="Signals Emitted">
        <.tag_list items={@project.signals_emitted} />
      </.meta_section>

      <.meta_section :if={(@project.signals_subscribed || []) != []} label="Signals Subscribed">
        <.tag_list items={@project.signals_subscribed} />
      </.meta_section>

      <.meta_section :if={@project.topic} label="PubSub Topic">
        <span class="font-mono text-[9px] text-default">{@project.topic}</span>
      </.meta_section>

      <.meta_section :if={@project.architecture} label="Architecture">
        <.mono_block text={@project.architecture} />
      </.meta_section>

      <.meta_section :if={(@project.dependencies || []) != []} label="Dependencies">
        <.tag_list items={@project.dependencies} />
      </.meta_section>

      <div class="mt-4 pt-3 border-t border-border/50 space-y-1 text-[9px] text-muted">
        <div :if={@project.version}>
          v<span class="font-mono text-default">{@project.version}</span>
        </div>
        <div :if={@project.team_name}>
          Team: <span class="text-default">{@project.team_name}</span>
        </div>
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

  attr :key, :string, required: true
  attr :value, :any, required: true

  defp meta_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between text-[9px] mb-0.5">
      <span class="text-zinc-500">{@key}</span>
      <span class="text-zinc-300 font-mono">{@value}</span>
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

  attr :text, :string, required: true

  def mono_block(assigns) do
    ~H"""
    <div class="text-[9px] font-mono text-zinc-400 p-2 rounded bg-zinc-900 border border-zinc-800 whitespace-pre-wrap leading-relaxed">
      {@text}
    </div>
    """
  end

  defp artifact_count(project, key) do
    case Map.get(project, key) do
      nil -> 0
      list when is_list(list) -> length(list)
      _ -> 0
    end
  end
end
