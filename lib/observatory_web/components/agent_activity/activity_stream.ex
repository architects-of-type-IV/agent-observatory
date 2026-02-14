defmodule ObservatoryWeb.Components.AgentActivity.ActivityStream do
  @moduledoc """
  Renders a scrollable stream of agent activity events.
  """

  use Phoenix.Component
  import ObservatoryWeb.Components.AgentActivity.ActivityItem

  attr :events, :list, required: true
  attr :limit, :integer, default: 25
  attr :expanded_events, :list, default: []
  attr :now, :any, required: true

  def activity_stream(assigns) do
    ~H"""
    <div class="space-y-1">
      <div :if={@events == []} class="text-xs text-zinc-500 p-2">
        No activity yet
      </div>

      <div
        :for={event <- Enum.take(@events, @limit)}
        class="text-xs border-b border-zinc-800 last:border-0"
      >
        <.activity_item
          event={event}
          expanded={event.id in @expanded_events}
          now={@now}
        />
      </div>
    </div>
    """
  end
end
