defmodule ObservatoryWeb.Components.Observatory.ModelBadge do
  @moduledoc """
  Renders a model badge.
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardSessionHelpers

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
      class="text-[10px] font-mono text-indigo-500"
    >
      {short_model_name(@model)}
    </span>
    """
  end
end
