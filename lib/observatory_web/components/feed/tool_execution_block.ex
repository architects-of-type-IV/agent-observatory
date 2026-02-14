defmodule ObservatoryWeb.Components.Feed.ToolExecutionBlock do
  @moduledoc """
  Tool execution block - paired Pre/Post shown as single block with duration.
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardFormatHelpers
  alias ObservatoryWeb.DashboardFeedHelpers

  attr :pair, :map, required: true
  attr :selected_event, :map, default: nil
  attr :event_notes, :map, required: true
  attr :now, :any, required: true

  def tool_execution_block(assigns) do
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
end
