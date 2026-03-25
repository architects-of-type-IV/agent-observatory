defmodule IchorWeb.UI.Button do
  @moduledoc """
  Base button primitive. Wraps all ichor-btn variants.

  Variants: primary, muted (default), danger, brand
  Sizes: sm (default), xs
  """

  use Phoenix.Component

  attr :type, :string, default: "button"
  attr :variant, :string, default: "muted"
  attr :size, :string, default: "sm"
  attr :class, :string, default: ""

  attr :rest, :global,
    include: ~w(phx-click phx-value-id phx-value-session_id phx-value-session phx-target data-confirm disabled form)

  slot :inner_block, required: true

  @doc "Renders an ichor-styled button."
  def button(assigns) do
    ~H"""
    <button type={@type} class={"ichor-btn #{variant_class(@variant)} #{size_class(@size)} #{@class}"} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  @spec variant_class(String.t()) :: String.t()
  defp variant_class("primary"), do: "ichor-btn-primary"
  defp variant_class("danger"), do: "ichor-btn-danger"
  defp variant_class("success"), do: "ichor-btn-success"
  defp variant_class("brand"), do: "bg-brand/15 text-brand hover:bg-brand/25"
  defp variant_class(_), do: "ichor-btn-muted"

  @spec size_class(String.t()) :: String.t()
  defp size_class("xs"), do: "text-[9px]"
  defp size_class(_), do: ""
end
