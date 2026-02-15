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
      class="text-xs font-mono px-1.5 py-0.5 rounded bg-indigo-500/15 text-indigo-400 border border-indigo-500/30"
    >
      {short_model_name(@model)}
    </span>
    """
  end
end
