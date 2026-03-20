defmodule IchorWeb.Components.MesStatusComponents do
  @moduledoc """
  Status badges and action buttons for MES projects.
  """

  use Phoenix.Component

  attr :status, :atom, required: true

  def status_badge(%{status: :proposed} = assigns) do
    ~H"""
    <span class="px-1.5 py-0.5 text-[9px] font-semibold rounded bg-info/15 text-info uppercase tracking-wider">
      Proposed
    </span>
    """
  end

  def status_badge(%{status: :in_progress} = assigns) do
    ~H"""
    <span class="px-1.5 py-0.5 text-[9px] font-semibold rounded bg-brand/15 text-brand uppercase tracking-wider">
      Building
    </span>
    """
  end

  def status_badge(%{status: :compiled} = assigns) do
    ~H"""
    <span class="px-1.5 py-0.5 text-[9px] font-semibold rounded bg-success/15 text-success uppercase tracking-wider">
      Compiled
    </span>
    """
  end

  def status_badge(%{status: :loaded} = assigns) do
    ~H"""
    <span class="flex items-center gap-1 px-1.5 py-0.5 text-[9px] font-semibold rounded bg-success/15 text-success uppercase tracking-wider">
      <span class="w-1 h-1 rounded-full bg-success animate-pulse" /> Live
    </span>
    """
  end

  def status_badge(%{status: :failed} = assigns) do
    ~H"""
    <span class="px-1.5 py-0.5 text-[9px] font-semibold rounded bg-error/15 text-error uppercase tracking-wider">
      Failed
    </span>
    """
  end

  def status_badge(assigns) do
    ~H"""
    <span class="px-1.5 py-0.5 text-[9px] font-semibold rounded bg-raised text-muted uppercase tracking-wider">
      {@status}
    </span>
    """
  end

  attr :project, :map, required: true

  def action_button(%{project: %{status: :proposed}} = assigns) do
    ~H"""
    <button
      phx-click="mes_pick_up"
      phx-value-id={@project.id}
      class="px-2.5 py-1 text-[10px] font-semibold rounded bg-brand/15 text-brand hover:bg-brand/25 transition-colors"
    >
      Pick Up
    </button>
    """
  end

  def action_button(%{project: %{status: :compiled}} = assigns) do
    ~H"""
    <button
      phx-click="mes_load_plugin"
      phx-value-id={@project.id}
      class="px-2.5 py-1 text-[10px] font-semibold rounded bg-success/15 text-success hover:bg-success/25 transition-colors"
    >
      Load into BEAM
    </button>
    """
  end

  def action_button(assigns) do
    ~H"""
    """
  end
end
