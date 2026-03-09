defmodule ObservatoryWeb.Components.AgentActivity.PayloadDetail do
  @moduledoc """
  Renders detailed payload information for an activity event.
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardAgentActivityHelpers

  attr :event, :map, required: true

  def payload_detail(assigns) do
    assigns = assign(assigns, :details, format_payload_detail(assigns.event))

    ~H"""
    <div class="bg-base/80 rounded border border-border-subtle p-2 space-y-1 max-h-96 overflow-y-auto">
      <div :for={{key, value} <- @details} class="grid grid-cols-[auto_1fr] gap-2 text-xs">
        <span class="text-low font-semibold">{key}:</span>
        <pre class="text-high overflow-x-auto whitespace-pre-wrap break-words"><%= value %></pre>
      </div>
    </div>
    """
  end
end
