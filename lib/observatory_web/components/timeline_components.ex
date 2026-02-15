defmodule ObservatoryWeb.Components.TimelineComponents do
  @moduledoc """
  Timeline/swimlane view component for the Observatory dashboard.
  """

  use Phoenix.Component
  import ObservatoryWeb.ObservatoryComponents
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.DashboardTimelineHelpers

  attr :timeline, :list, required: true

  def timeline_view(assigns) do
    ~H"""
    <div class="p-4">
      <.empty_state
        :if={@timeline == []}
        title="No tool activity yet"
        description="Timeline will show tool executions over time as horizontal bars. Click blocks to inspect."
      />

      <div :if={@timeline != []} class="space-y-4">
        <%!-- Color legend --%>
        <div class="flex items-center gap-3 text-xs text-zinc-500 pb-2 border-b border-zinc-800">
          <span class="font-semibold text-zinc-400">Legend:</span>
          <div class="flex items-center gap-1.5">
            <span class="w-3 h-3 rounded bg-blue-500/60"></span>
            <span>Bash</span>
          </div>
          <div class="flex items-center gap-1.5">
            <span class="w-3 h-3 rounded bg-emerald-500/60"></span>
            <span>Read/Write/Edit</span>
          </div>
          <div class="flex items-center gap-1.5">
            <span class="w-3 h-3 rounded bg-amber-500/60"></span>
            <span>Search</span>
          </div>
          <div class="flex items-center gap-1.5">
            <span class="w-3 h-3 rounded bg-purple-500/60"></span>
            <span>Task/Team</span>
          </div>
          <div class="flex items-center gap-1.5">
            <span class="w-3 h-3 rounded bg-zinc-800"></span>
            <span>Idle</span>
          </div>
        </div>

        <% global_start = List.first(@timeline).start_time %>
        <% global_end =
          List.last(Enum.sort_by(@timeline, & &1.start_time, {:desc, DateTime})).end_time %>

        <div :for={{session, idx} <- Enum.with_index(@timeline)} class="space-y-2">
          <div class="flex items-center gap-2">
            <% {bg, _b, _t} = session_color(session.session_id) %>
            <span class={"w-2 h-2 rounded-full #{bg}"}></span>
            <span class="text-xs font-mono text-zinc-400">
              {session.source_app}:{short_session(session.session_id)}
            </span>
            <span class="text-xs text-zinc-600">{session_duration_sec(session.duration_sec)}</span>
          </div>

          <div class={"relative h-8 rounded border border-zinc-800 overflow-hidden #{if rem(idx, 2) == 0, do: "bg-zinc-900", else: "bg-zinc-900/50"}"}>
            <% positioned_blocks = calculate_block_positions(session, global_start, global_end) %>
            <div
              :for={block <- positioned_blocks}
              class="absolute top-1 h-6 group"
              style={"left: #{block.left_pct}%; width: #{block.width_pct}%"}
            >
              <% block_class =
                if block[:type] == :idle,
                  do: "h-full w-full rounded bg-zinc-800",
                  else:
                    "h-full w-full rounded #{tool_color(block[:tool_name])} cursor-pointer hover:opacity-80 transition flex items-center justify-center" %>
              <% block_title =
                if block[:type] == :tool, do: "#{block[:tool_name]}: #{block[:summary]}", else: "idle" %>
              <% show_label = block[:type] == :tool && block.width_pct > 5 %>
              <div
                :if={block[:type] == :tool && block[:event_id]}
                phx-click="select_timeline_event"
                phx-value-id={block[:event_id]}
                class={block_class}
                title={block_title}
              >
                <span :if={show_label} class="text-xs font-mono text-white/90 truncate px-1">
                  {block[:tool_name]}
                </span>
              </div>
              <div
                :if={block[:type] == :idle || !block[:event_id]}
                class={block_class}
                title={block_title}
              >
              </div>
            </div>
          </div>
        </div>

        <%!-- Time axis --%>
        <div class="relative h-4 mt-2">
          <% labels = time_axis_labels(global_start, global_end, 10) %>
          <div :for={label <- labels} class="absolute" style={"left: #{label.position_pct}%"}>
            <span class="text-xs text-zinc-600">{label.label}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
