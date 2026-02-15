defmodule ObservatoryWeb.Components.Feed.SessionGroup do
  @moduledoc """
  Session group component - collapsible group with header showing session metadata.
  """

  use Phoenix.Component
  import ObservatoryWeb.ObservatoryComponents
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.DashboardSessionHelpers
  import ObservatoryWeb.Components.Feed.ToolExecutionBlock
  import ObservatoryWeb.Components.Feed.StandaloneEvent
  alias ObservatoryWeb.DashboardFeedHelpers

  attr :group, :map, required: true
  attr :selected_event, :map, default: nil
  attr :event_notes, :map, required: true
  attr :now, :any, required: true

  def session_group(assigns) do
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
      <div
        :if={@group.session_start}
        class="px-3 py-1.5 bg-green-500/10 border-l-2 border-green-500/50"
      >
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

  defp session_border_color(session_id) do
    {_bg, border, _text} = session_color(session_id)
    border
  end
end
