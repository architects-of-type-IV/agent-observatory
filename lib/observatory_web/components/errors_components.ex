defmodule ObservatoryWeb.Components.ErrorsComponents do
  @moduledoc """
  Errors view component for the Observatory dashboard.
  """

  use Phoenix.Component
  import ObservatoryWeb.ObservatoryComponents
  import ObservatoryWeb.DashboardFormatHelpers

  attr :errors, :list, required: true
  attr :error_groups, :list, required: true
  attr :now, :any, required: true

  def errors_view(assigns) do
    ~H"""
    <div class="p-4">
      <.empty_state
        :if={@errors == []}
        title="No errors yet"
        description="Tool failures from PostToolUseFailure events will appear here grouped by tool"
      />

      <div :if={@errors != []} class="space-y-4">
        <div :for={group <- @error_groups} class="p-4 rounded-lg border border-red-500/20 bg-red-500/5">
          <div class="flex items-center justify-between mb-3">
            <div class="flex items-center gap-2">
              <span class="text-sm font-semibold text-red-400">{group.tool}</span>
              <span class="px-2 py-0.5 text-xs rounded bg-red-500/40 text-red-300 animate-pulse">{group.count} errors</span>
              <button
                phx-click="jump_to_timeline"
                phx-value-session_id={group.latest.session_id}
                class="text-xs px-2 py-0.5 rounded bg-zinc-700/50 text-zinc-400 hover:bg-zinc-700 transition"
              >
                View in Timeline
              </button>
              <button
                phx-click="jump_to_feed"
                phx-value-session_id={group.latest.session_id}
                class="text-xs px-2 py-0.5 rounded bg-zinc-700/50 text-zinc-400 hover:bg-zinc-700 transition"
              >
                View in Feed
              </button>
            </div>
            <span class="text-xs text-zinc-500">{relative_time(group.latest.timestamp, @now)}</span>
          </div>
          <div class="space-y-2">
            <div :for={err <- Enum.take(group.errors, 5)} class="p-2 rounded bg-zinc-900/50 border border-zinc-800">
              <div class="flex items-center justify-between mb-1">
                <% {bg, _b, _t} = session_color(err.session_id) %>
                <span class={"w-2 h-2 rounded-full #{bg}"}></span>
                <span class="text-xs font-mono text-zinc-500">{short_session(err.session_id)}</span>
                <span class="text-xs text-zinc-600">{relative_time(err.timestamp, @now)}</span>
              </div>
              <p class="text-xs text-zinc-300 ml-4 break-words">{err.error}</p>
            </div>
            <p :if={length(group.errors) > 5} class="text-xs text-zinc-600 text-center">
              + {length(group.errors) - 5} more errors
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
