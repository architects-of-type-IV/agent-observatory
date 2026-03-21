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
end
