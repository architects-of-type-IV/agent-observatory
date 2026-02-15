defmodule ObservatoryWeb.Components.AnalyticsComponents do
  @moduledoc """
  Analytics/tool performance view component for the Observatory dashboard.
  """

  use Phoenix.Component
  import ObservatoryWeb.ObservatoryComponents
  import ObservatoryWeb.DashboardFormatHelpers

  attr :analytics, :list, required: true

  def analytics_view(assigns) do
    ~H"""
    <div class="p-4">
      <.empty_state
        :if={@analytics == []}
        title="No tool usage yet"
        description="Performance analytics appear when agents execute tools with PreToolUse/PostToolUse events"
      />

      <div :if={@analytics != []} class="space-y-3">
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="border-b border-zinc-800">
              <tr class="text-left">
                <th class="pb-2 pr-4 text-xs font-semibold text-zinc-500 uppercase">Tool</th>
                <th class="pb-2 pr-4 text-xs font-semibold text-zinc-500 uppercase text-right">
                  Uses
                </th>
                <th class="pb-2 pr-4 text-xs font-semibold text-zinc-500 uppercase text-right">
                  Success
                </th>
                <th class="pb-2 pr-4 text-xs font-semibold text-zinc-500 uppercase text-right">
                  Failures
                </th>
                <th class="pb-2 pr-4 text-xs font-semibold text-zinc-500 uppercase text-right">
                  Fail %
                </th>
                <th class="pb-2 text-xs font-semibold text-zinc-500 uppercase text-right">
                  Avg Duration
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={stat <- @analytics}
                phx-click="filter_analytics_tool"
                phx-value-tool={stat.tool}
                class="border-b border-zinc-800/50 hover:bg-zinc-900/50 cursor-pointer transition"
              >
                <td class="py-2 pr-4 font-mono text-zinc-300">{stat.tool}</td>
                <td class="py-2 pr-4 text-right text-zinc-400">{stat.total_uses}</td>
                <td class="py-2 pr-4 text-right text-emerald-400">{stat.successes}</td>
                <td class="py-2 pr-4 text-right text-red-400">{stat.failures}</td>
                <% fail_class =
                  if stat.failure_rate > 0.3,
                    do: "py-2 pr-4 text-right text-red-400",
                    else: "py-2 pr-4 text-right text-zinc-500" %>
                <td class={fail_class}>
                  {Float.round(stat.failure_rate * 100, 0)}%
                </td>
                <td class="py-2 text-right text-zinc-400">
                  {if stat.avg_duration_ms, do: format_duration(stat.avg_duration_ms), else: "-"}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end
end
