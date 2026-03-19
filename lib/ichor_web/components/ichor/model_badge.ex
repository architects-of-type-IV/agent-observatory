defmodule IchorWeb.Components.Ichor.ModelBadge do
  @moduledoc """
  Renders a model badge.
  """

  use Phoenix.Component
  import IchorWeb.DashboardSessionHelpers

  @doc """
  Renders a model badge.

  ## Examples

      <.model_badge model="opus" />
  """
  attr :model, :string, default: nil

  def model_badge(assigns) do
    ~H"""
    <span
      :if={@model}
      class="text-[10px] font-mono text-interactive"
    >
      {short_model_name(@model)}
    </span>
    """
  end
end
