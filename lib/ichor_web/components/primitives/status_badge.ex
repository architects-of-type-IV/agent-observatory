defmodule IchorWeb.Components.Primitives.StatusBadge do
  @moduledoc """
  Primitive badge component for status labels.

  Renders a small pill with a consistent size and color-mapped styling.
  Color names map to the project's Tailwind semantic color tokens.
  """

  use Phoenix.Component

  @doc """
  Renders a small status badge.

  ## Examples

      <.status_badge label="mcp" color="interactive" />
      <.status_badge label="done" color="success" />
      <.status_badge label="failed" color="error" />
  """
  attr :label, :string, required: true
  attr :color, :string, default: "muted"
  attr :class, :string, default: ""

  def status_badge(assigns) do
    assigns = assign(assigns, :color_classes, color_classes(assigns.color))

    ~H"""
    <span class={"text-[9px] px-1.5 py-0.5 rounded #{@color_classes} #{@class}"}>
      {@label}
    </span>
    """
  end

  @spec color_classes(String.t()) :: String.t()
  defp color_classes("success"), do: "bg-success/15 text-success"
  defp color_classes("error"), do: "bg-error/15 text-error"
  defp color_classes("brand"), do: "bg-brand/10 text-brand"
  defp color_classes("interactive"), do: "bg-interactive/15 text-interactive"
  defp color_classes("warning"), do: "bg-warning/15 text-warning"
  defp color_classes("info"), do: "bg-info/15 text-info"
  defp color_classes("muted"), do: "text-muted"
  defp color_classes(_), do: "text-muted"
end
