defmodule ObservatoryWeb.Components.Observatory.HealthWarnings do
  @moduledoc """
  Renders health warnings for an agent.
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardAgentHealthHelpers

  @doc """
  Renders health warnings for an agent.

  ## Examples

      <.health_warnings issues={member[:health_issues]} />
  """
  attr :issues, :list, required: true

  def health_warnings(assigns) do
    ~H"""
    <div :if={@issues != []} class="mt-2 ml-4 space-y-0.5">
      <div :for={issue <- @issues} class="text-xs text-red-400/80">
        {format_issue(issue)}
      </div>
    </div>
    """
  end
end
