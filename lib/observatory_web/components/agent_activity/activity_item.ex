defmodule ObservatoryWeb.Components.AgentActivity.ActivityItem do
  @moduledoc """
  Renders a single activity event with expandable payload detail.
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.DashboardAgentActivityHelpers
  import ObservatoryWeb.Components.AgentActivity.PayloadDetail

  attr :event, :map, required: true
  attr :expanded, :boolean, default: false
  attr :now, :any, required: true

  def activity_item(assigns) do
    ~H"""
    <div class="hover:bg-zinc-800/30 transition">
      <%!-- Summary row (always visible) --%>
      <div
        phx-click="toggle_event_detail"
        phx-value-id={@event.id}
        class="p-2 cursor-pointer flex items-start gap-2"
      >
        <span class="text-zinc-600 font-mono shrink-0">{format_time(@event.inserted_at)}</span>
        <span class="flex-1 text-zinc-300">{summarize_event(@event)}</span>
        <span class="text-zinc-600 shrink-0">{relative_time(@event.inserted_at, @now)}</span>
        <span class="text-zinc-600 shrink-0">{if @expanded, do: "▼", else: "▶"}</span>
      </div>

      <%!-- Expandable payload detail --%>
      <div :if={@expanded} class="px-2 pb-2">
        <.payload_detail event={@event} />
      </div>
    </div>
    """
  end
end
