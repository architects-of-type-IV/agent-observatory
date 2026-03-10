defmodule IchorWeb.Components.ArchonComponents.Icons do
  @moduledoc false

  use Phoenix.Component

  attr :name, :string, required: true

  def hud_icon(%{name: "grid"} = assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <rect x="3" y="3" width="7" height="7" /><rect x="14" y="3" width="7" height="7" />
      <rect x="3" y="14" width="7" height="7" /><rect x="14" y="14" width="7" height="7" />
    </svg>
    """
  end

  def hud_icon(%{name: "layers"} = assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <path d="M12 2L2 7l10 5 10-5-10-5z" /><path d="M2 17l10 5 10-5" /><path d="M2 12l10 5 10-5" />
    </svg>
    """
  end

  def hud_icon(%{name: "mail"} = assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <rect x="2" y="4" width="20" height="16" rx="2" /><path d="M22 4L12 13 2 4" />
    </svg>
    """
  end

  def hud_icon(%{name: "pulse"} = assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <path d="M3 12h4l3-9 4 18 3-9h4" />
    </svg>
    """
  end

  def hud_icon(%{name: "terminal"} = assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <rect x="2" y="3" width="20" height="18" rx="2" /><path d="M6 9l4 3-4 3" /><line
        x1="13"
        y1="15"
        x2="18"
        y2="15"
      />
    </svg>
    """
  end

  def hud_icon(%{name: "search"} = assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <circle cx="11" cy="11" r="8" /><line x1="21" y1="21" x2="16.65" y2="16.65" />
    </svg>
    """
  end

  def hud_icon(%{name: "brain"} = assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <path d="M12 2a7 7 0 0 1 7 7c0 2.5-1.3 4.7-3.2 6H8.2C6.3 13.7 5 11.5 5 9a7 7 0 0 1 7-7z" />
      <path d="M9 22v-4h6v4" /><path d="M9 18h6" />
    </svg>
    """
  end

  def hud_icon(%{name: "command"} = assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <path d="M18 3a3 3 0 0 0-3 3v12a3 3 0 0 0 3 3 3 3 0 0 0 3-3 3 3 0 0 0-3-3H6a3 3 0 0 0-3 3 3 3 0 0 0 3 3 3 3 0 0 0 3-3V6a3 3 0 0 0-3-3 3 3 0 0 0-3 3 3 3 0 0 0 3 3h12a3 3 0 0 0 3-3 3 3 0 0 0-3-3z" />
    </svg>
    """
  end

  def hud_icon(assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <circle cx="12" cy="12" r="10" />
    </svg>
    """
  end

  attr :active, :boolean, default: false

  def archon_icon(assigns) do
    ~H"""
    <svg
      class={[
        "archon-fab-icon",
        if(@active, do: "archon-fab-icon-active", else: "archon-fab-icon-idle")
      ]}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
    >
      <path d="M12 2L2 7l10 5 10-5-10-5z" />
      <path d="M2 17l10 5 10-5" />
      <path d="M2 12l10 5 10-5" />
    </svg>
    """
  end
end
