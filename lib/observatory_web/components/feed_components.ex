defmodule ObservatoryWeb.Components.FeedComponents do
  @moduledoc """
  Feed/event stream view component for the Observatory dashboard.
  """

  use Phoenix.Component
  import ObservatoryWeb.ObservatoryComponents
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.DashboardSessionHelpers
  alias ObservatoryWeb.DashboardFeedHelpers

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

            <span class="text-xs font-mono text-zinc-600 shrink-0 w-14 text-right" title={format_time(event.inserted_at)}>
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

            <span :if={Map.has_key?(@event_notes, event.id)} class="text-amber-400 shrink-0" title="Has note">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
              </svg>
            </span>

            <span
              class={"text-xs font-mono px-1 rounded #{duration_color(event.duration_ms)} shrink-0 w-12 text-right"}
            >
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

  # Session group component - collapsible group with header showing session metadata
  attr :group, :map, required: true
  attr :selected_event, :map, default: nil
  attr :event_notes, :map, required: true
  attr :now, :any, required: true

  defp session_group(assigns) do
    ~H"""
    <div class={"border-l-4 #{session_border_color(@group.session_id)} bg-zinc-900/40 rounded"}>
      <!-- Header -->
      <div class="px-3 py-2 flex items-center gap-2 border-b border-zinc-800">
        <% {bg, _border, _text} = session_color(@group.session_id) %>
        <span class={"w-2 h-2 rounded-full shrink-0 #{bg}"}></span>

        <span class="text-xs font-mono text-zinc-400 shrink-0">
          {short_session(@group.session_id)}
        </span>

        <.model_badge :if={@group.model} model={@group.model} />

        <span class="text-xs font-mono text-zinc-600 shrink-0">
          {@group.event_count} events
        </span>

        <span :if={@group.is_active} class="text-xs font-mono text-amber-400 shrink-0">
          Active
        </span>

        <span class="flex-1"></span>

        <span :if={@group.cwd} class="text-xs font-mono text-zinc-600 truncate" title={@group.cwd}>
          {abbreviate_cwd(@group.cwd)}
        </span>
      </div>

      <!-- Session start banner -->
      <div :if={@group.session_start} class="px-3 py-1.5 bg-green-500/10 border-l-2 border-green-500/50">
        <div class="flex items-center gap-2 text-xs">
          <span class="text-green-400 font-mono">Session Started</span>
          <span class="text-zinc-500">•</span>
          <span class="text-zinc-400">{format_time(@group.session_start.inserted_at)}</span>
          <span :if={@group.model} class="text-zinc-500">•</span>
          <span :if={@group.model} class="text-zinc-400">{@group.model}</span>
        </div>
      </div>

      <!-- Tool execution blocks and other events -->
      <div class="px-3 py-2 space-y-1">
        <% paired_ids = DashboardFeedHelpers.get_paired_tool_use_ids(@group.tool_pairs) %>

        <!-- Render tool pairs as blocks -->
        <.tool_execution_block
          :for={pair <- @group.tool_pairs}
          pair={pair}
          selected_event={@selected_event}
          event_notes={@event_notes}
          now={@now}
        />

        <!-- Render standalone events (not part of tool pairs) -->
        <% standalone = DashboardFeedHelpers.get_standalone_events(@group.events, paired_ids) %>
        <.standalone_event
          :for={event <- standalone}
          event={event}
          selected_event={@selected_event}
          event_notes={@event_notes}
          now={@now}
        />
      </div>

      <!-- Session end banner -->
      <div :if={@group.session_end} class="px-3 py-1.5 bg-red-500/10 border-l-2 border-red-500/50">
        <div class="flex items-center gap-2 text-xs">
          <span class="text-red-400 font-mono">Session Ended</span>
          <span class="text-zinc-500">•</span>
          <span class="text-zinc-400">{format_time(@group.session_end.inserted_at)}</span>
          <span :if={@group.total_duration_ms} class="text-zinc-500">•</span>
          <span :if={@group.total_duration_ms} class="text-zinc-400">
            Duration: {format_duration(@group.total_duration_ms)}
          </span>
        </div>
      </div>
    </div>
    """
  end

  # Tool execution block - paired Pre/Post shown as single block with duration
  attr :pair, :map, required: true
  attr :selected_event, :map, default: nil
  attr :event_notes, :map, required: true
  attr :now, :any, required: true

  defp tool_execution_block(assigns) do
    ~H"""
    <div class="ml-4 border-l-2 border-zinc-700 pl-3 py-1 space-y-1">
      <!-- Tool name and status header -->
      <div class="flex items-center gap-2">
        <span class="text-xs font-mono text-indigo-400 shrink-0">
          {@pair.tool_name}
        </span>

        <!-- Status indicator -->
        <span :if={@pair.status == :in_progress} class="text-xs font-mono text-amber-400 shrink-0">
          Running... ({format_duration(DashboardFeedHelpers.elapsed_time_ms(@pair.pre, @now))})
        </span>

        <span :if={@pair.status == :success} class={"text-xs font-mono shrink-0 #{duration_color(@pair.duration_ms)}"}>
          {format_duration(@pair.duration_ms)}
        </span>

        <span :if={@pair.status == :failure} class="text-xs font-mono text-red-400 shrink-0">
          Failed
        </span>

        <span class="flex-1"></span>

        <span class="text-xs font-mono text-zinc-600 shrink-0">
          {relative_time(@pair.pre.inserted_at, @now)}
        </span>
      </div>

      <!-- Pre event (clickable) -->
      <div
        class={"flex items-center gap-2 px-2 py-1 rounded cursor-pointer transition-all hover:bg-zinc-800/50 text-xs #{if @selected_event && @selected_event.id == @pair.pre.id, do: "bg-zinc-800/80 ring-1 ring-indigo-500/40", else: ""}"}
        phx-click="select_event"
        phx-value-id={@pair.pre.id}
      >
        <span class="text-amber-400 font-mono shrink-0">START</span>
        <span class="text-zinc-400 truncate flex-1">
          {event_summary(@pair.pre)}
        </span>
        <span :if={Map.has_key?(@event_notes, @pair.pre.id)} class="text-amber-400 shrink-0" title="Has note">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" viewBox="0 0 20 20" fill="currentColor">
            <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
          </svg>
        </span>
      </div>

      <!-- Post event (clickable) - if exists -->
      <div
        :if={@pair.post}
        class={"flex items-center gap-2 px-2 py-1 rounded cursor-pointer transition-all hover:bg-zinc-800/50 text-xs #{if @selected_event && @selected_event.id == @pair.post.id, do: "bg-zinc-800/80 ring-1 ring-indigo-500/40", else: ""}"}
        phx-click="select_event"
        phx-value-id={@pair.post.id}
      >
        <span class={"font-mono shrink-0 #{if @pair.status == :failure, do: "text-red-400", else: "text-emerald-400"}"}>
          {if @pair.status == :failure, do: "FAIL", else: "DONE"}
        </span>
        <span class="text-zinc-400 truncate flex-1">
          {event_summary(@pair.post)}
        </span>
        <span :if={Map.has_key?(@event_notes, @pair.post.id)} class="text-amber-400 shrink-0" title="Has note">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" viewBox="0 0 20 20" fill="currentColor">
            <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
          </svg>
        </span>
      </div>
    </div>
    """
  end

  # Standalone event (not part of a tool pair)
  attr :event, :map, required: true
  attr :selected_event, :map, default: nil
  attr :event_notes, :map, required: true
  attr :now, :any, required: true

  defp standalone_event(assigns) do
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

  defp session_border_color(session_id) do
    {_bg, border, _text} = session_color(session_id)
    border
  end
end
