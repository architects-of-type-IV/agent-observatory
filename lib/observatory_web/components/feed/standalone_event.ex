defmodule ObservatoryWeb.Components.Feed.StandaloneEvent do
  @moduledoc """
  Standalone event component (not part of a tool pair).
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardFormatHelpers

  attr :event, :map, required: true
  attr :selected_event, :map, default: nil
  attr :event_notes, :map, required: true
  attr :now, :any, required: true

  def standalone_event(assigns) do
    ~H"""
    <div
      class={"flex items-center gap-2 px-2 py-1 rounded cursor-pointer transition-all hover:bg-zinc-900/80 group text-xs #{if @selected_event && @selected_event.id == @event.id, do: "bg-zinc-800/80 ring-1 ring-indigo-500/40", else: ""}"}
      phx-click="select_event"
      phx-value-id={@event.id}
    >
      <span class="text-xs font-mono text-zinc-600 shrink-0 w-12 text-right">
        {relative_time(@event.inserted_at, @now)}
      </span>

      <% {label, badge_class} = event_type_label(@event.hook_event_type) %>
      <span class={"text-xs font-mono px-1.5 py-0 rounded shrink-0 #{badge_class}"}>
        {label}
      </span>

      <span class="text-zinc-400 truncate flex-1 min-w-0 group-hover:text-zinc-300">
        {@event.summary || event_summary(@event)}
      </span>

      <span :if={Map.has_key?(@event_notes, @event.id)} class="text-amber-400 shrink-0" title="Has note">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" viewBox="0 0 20 20" fill="currentColor">
          <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
        </svg>
      </span>
    </div>
    """
  end
end
