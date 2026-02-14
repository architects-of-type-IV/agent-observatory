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
    <div class="bg-zinc-900/80 rounded border border-zinc-700 p-2 space-y-1 max-h-96 overflow-y-auto">
      <div :for={{key, value} <- @details} class="grid grid-cols-[auto_1fr] gap-2 text-xs">
        <span class="text-zinc-500 font-semibold">{key}:</span>
        <pre class="text-zinc-300 overflow-x-auto whitespace-pre-wrap break-words"><%= value %></pre>
      </div>
    </div>
    """
  end
end
