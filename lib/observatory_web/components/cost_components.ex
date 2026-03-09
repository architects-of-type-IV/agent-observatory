defmodule ObservatoryWeb.Components.CostComponents do
  @moduledoc """
  Cost dashboard components showing token usage, model breakdown, and per-agent costs.
  """
  use Phoenix.Component

  @doc "Renders the cost dashboard view."
  attr :cost_data, :map, required: true

  def cost_view(assigns) do
    ~H"""
    <%
      data = @cost_data
      by_model = data[:by_model] || []
      by_session = data[:by_session] || []
      totals = data[:totals] || %{}
      total_cost = totals[:cost_cents] || 0
      total_input = totals[:input_tokens] || 0
      total_output = totals[:output_tokens] || 0
      total_cache_read = totals[:cache_read] || 0
      max_session_cost = by_session |> Enum.map(& &1.cost_cents) |> Enum.max(fn -> 1 end)
    %>
    <div class="flex flex-col gap-3 p-3 h-full overflow-y-auto">
      <%!-- Summary Cards --%>
      <div class="grid grid-cols-4 gap-2">
        <div class="bg-base/50 border border-border rounded px-3 py-2">
          <div class="text-[9px] text-low uppercase tracking-wider">Total Cost</div>
          <div class="text-lg font-bold text-success">{format_cost(total_cost)}</div>
        </div>
        <div class="bg-base/50 border border-border rounded px-3 py-2">
          <div class="text-[9px] text-low uppercase tracking-wider">Input Tokens</div>
          <div class="text-lg font-bold text-info">{format_tokens(total_input)}</div>
        </div>
        <div class="bg-base/50 border border-border rounded px-3 py-2">
          <div class="text-[9px] text-low uppercase tracking-wider">Output Tokens</div>
          <div class="text-lg font-bold text-brand">{format_tokens(total_output)}</div>
        </div>
        <div class="bg-base/50 border border-border rounded px-3 py-2">
          <div class="text-[9px] text-low uppercase tracking-wider">Cache Reads</div>
          <div class="text-lg font-bold text-violet">{format_tokens(total_cache_read)}</div>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-3 flex-1 min-h-0">
        <%!-- Model Breakdown --%>
        <div class="bg-base/50 border border-border rounded flex flex-col overflow-hidden">
          <div class="px-3 py-1.5 border-b border-border shrink-0">
            <h4 class="text-[10px] font-semibold text-low uppercase tracking-wider">By Model</h4>
          </div>
          <div class="flex-1 overflow-y-auto p-2">
            <div :if={by_model == []} class="text-[10px] text-muted p-2">No cost data yet</div>
            <div :for={model <- by_model} class="flex items-center gap-2 py-1.5 px-1 border-b border-border/50 last:border-0">
              <span class={"w-2 h-2 rounded-full shrink-0 #{model_color(model.model)}"}></span>
              <div class="flex-1 min-w-0">
                <div class="text-[11px] text-high font-mono truncate">{short_model(model.model)}</div>
                <div class="flex gap-3 text-[9px] text-low">
                  <span>{format_tokens(model.input_tokens)} in</span>
                  <span>{format_tokens(model.output_tokens)} out</span>
                  <span>{model.count} calls</span>
                </div>
              </div>
              <span class="text-[11px] font-semibold text-success shrink-0">{format_cost(model.cost_cents)}</span>
            </div>
          </div>
        </div>

        <%!-- Per-Session Costs --%>
        <div class="bg-base/50 border border-border rounded flex flex-col overflow-hidden">
          <div class="px-3 py-1.5 border-b border-border shrink-0">
            <h4 class="text-[10px] font-semibold text-low uppercase tracking-wider">By Agent</h4>
          </div>
          <div class="flex-1 overflow-y-auto p-2">
            <div :if={by_session == []} class="text-[10px] text-muted p-2">No cost data yet</div>
            <div :for={session <- by_session} class="py-1.5 px-1 border-b border-border/50 last:border-0">
              <div class="flex items-center justify-between mb-0.5">
                <span class="text-[10px] text-high font-mono truncate max-w-[180px]">{session.label}</span>
                <span class="text-[10px] font-semibold text-success">{format_cost(session.cost_cents)}</span>
              </div>
              <div class="h-1.5 bg-raised rounded-full overflow-hidden">
                <div
                  class="h-full bg-success/60 rounded-full transition-all"
                  style={"width: #{cost_bar_width(session.cost_cents, max_session_cost)}%"}
                />
              </div>
              <div class="flex gap-3 text-[9px] text-muted mt-0.5">
                <span :if={session.model} class="text-interactive/60">{short_model(session.model)}</span>
                <span>{format_tokens(session.input_tokens)} in</span>
                <span>{format_tokens(session.output_tokens)} out</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_cost(cents) when is_number(cents) and cents >= 100 do
    "$#{Float.round(cents / 100, 2)}"
  end

  defp format_cost(cents) when is_number(cents), do: "#{cents}c"
  defp format_cost(_), do: "$0"

  defp format_tokens(n) when is_number(n) and n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  defp format_tokens(n) when is_number(n) and n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  defp format_tokens(n) when is_number(n), do: "#{n}"
  defp format_tokens(_), do: "0"

  defp short_model(nil), do: "unknown"
  defp short_model(model) when is_binary(model) do
    model
    |> String.replace(~r/^claude-/, "")
    |> String.replace(~r/-\d{8}$/, "")
    |> String.replace(~r/^anthropic\//, "")
  end

  defp model_color(model) when is_binary(model) do
    cond do
      String.contains?(model, "opus") -> "bg-violet"
      String.contains?(model, "sonnet") -> "bg-info"
      String.contains?(model, "haiku") -> "bg-success"
      true -> "bg-default"
    end
  end

  defp model_color(_), do: "bg-default"

  defp cost_bar_width(cost, max) when is_number(cost) and is_number(max) and max > 0 do
    Float.round(cost / max * 100, 1)
  end

  defp cost_bar_width(_, _), do: 0
end
