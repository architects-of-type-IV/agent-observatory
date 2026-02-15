defmodule ObservatoryWeb.Components.Feed.FeedView do
  @moduledoc """
  Main feed view component for displaying event streams.
  """

  use Phoenix.Component
  import ObservatoryWeb.ObservatoryComponents
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.Components.Feed.SessionGroup

  attr :visible_events, :list, required: true
  attr :selected_event, :map, default: nil
  attr :event_notes, :map, required: true
  attr :now, :any, required: true
  attr :feed_grouped, :boolean, default: false
  attr :feed_groups, :list, default: []

  def feed_view(assigns) do
    ~H"""
    <div class="p-3 space-y-2">
      <!-- Toggle button -->
      <div class="flex items-center gap-2 pb-2 border-b border-zinc-800">
        <button
          phx-click="toggle_feed_grouping"
          class="text-xs font-mono px-2 py-1 rounded bg-zinc-800 hover:bg-zinc-700 text-zinc-300 transition-colors"
        >
          {if @feed_grouped, do: "Chronological", else: "Group by Agent"}
        </button>
      </div>

      <.empty_state
        :if={Enum.empty?(@visible_events)}
        title="Waiting for agent activity..."
        description="Hook events will stream here in real-time. Try running agents or use keyboard shortcuts (press ?) for help."
      />
      
    <!-- Grouped view -->
      <div :if={@feed_grouped && !Enum.empty?(@feed_groups)} class="space-y-3" id="grouped-feed">
        <.session_group
          :for={group <- @feed_groups}
          group={group}
          selected_event={@selected_event}
          event_notes={@event_notes}
          now={@now}
        />
      </div>
      
    <!-- Chronological view -->
      <div :if={!@feed_grouped} class="space-y-px" id="event-list">
        <div :for={event <- @visible_events} id={"ev-#{event.id}"}>
          <div
            class={"flex items-center gap-2 px-3 py-1.5 rounded cursor-pointer transition-all hover:bg-zinc-900/80 group #{if @selected_event && @selected_event.id == event.id, do: "bg-zinc-800/80 ring-1 ring-indigo-500/40", else: ""} #{if is_team_tool?(event.tool_name), do: "border-l-2 border-cyan-500/30", else: ""}"}
            phx-click="select_event"
            phx-value-id={event.id}
          >
            <% {bg, _border, _text} = session_color(event.session_id) %>
            <span class={"w-1.5 h-1.5 rounded-full shrink-0 #{bg}"}></span>

            <span
              class="text-xs font-mono text-zinc-600 shrink-0 w-14 text-right"
              title={format_time(event.inserted_at)}
            >
              {relative_time(event.inserted_at, @now)}
            </span>

            <% {label, badge_class} = event_type_label(event.hook_event_type) %>
            <span class={"text-xs font-mono px-1.5 py-0 rounded shrink-0 #{badge_class}"}>
              {label}
            </span>

            <span
              :if={event.tool_name}
              class={"text-xs font-mono shrink-0 #{if is_team_tool?(event.tool_name), do: "text-cyan-400", else: "text-indigo-400"}"}
            >
              {event.tool_name}
            </span>

            <span class="text-sm text-zinc-400 truncate flex-1 min-w-0 group-hover:text-zinc-300">
              {event.summary || event_summary(event)}
            </span>

            <span
              :if={Map.has_key?(@event_notes, event.id)}
              class="text-amber-400 shrink-0"
              title="Has note"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-3.5 w-3.5"
                viewBox="0 0 20 20"
                fill="currentColor"
              >
                <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
              </svg>
            </span>

            <span class={"text-xs font-mono px-1 rounded #{duration_color(event.duration_ms)} shrink-0 w-12 text-right"}>
              {if event.duration_ms, do: format_duration(event.duration_ms), else: "-"}
            </span>

            <span class="text-xs font-mono text-zinc-700 shrink-0 hidden lg:inline">
              {event.source_app}:{short_session(event.session_id)}
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
