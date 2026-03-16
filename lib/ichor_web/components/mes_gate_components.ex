defmodule IchorWeb.Components.MesGateComponents do
  @moduledoc """
  Gate check readiness report for Genesis pipeline transitions.
  """

  use Phoenix.Component

  attr :report, :map, required: true

  def gate_report(assigns) do
    ~H"""
    <div class="mt-3 p-3 rounded bg-surface border border-subtle">
      <div class="flex items-center justify-between mb-2">
        <h4 class="text-[9px] font-semibold text-low uppercase tracking-wider">
          Gate Readiness Report
        </h4>
        <span class="text-[9px] font-mono text-muted uppercase">
          {Map.get(@report, "current_status", "unknown")}
        </span>
      </div>

      <div class="grid grid-cols-2 gap-1.5 mb-3">
        <.gate_metric label="ADRs" value={@report["adrs"]} />
        <.gate_metric label="Accepted ADRs" value={@report["accepted_adrs"]} />
        <.gate_metric label="Features" value={@report["features"]} />
        <.gate_metric label="Use Cases" value={@report["use_cases"]} />
        <.gate_metric label="Checkpoints" value={@report["checkpoints"]} />
        <.gate_metric label="Phases" value={@report["phases"]} />
      </div>

      <div class="flex flex-col gap-1">
        <.gate_verdict label="Ready for Define" ready={@report["ready_for_define"]} />
        <.gate_verdict label="Ready for Build" ready={@report["ready_for_build"]} />
        <.gate_verdict label="Ready for Complete" ready={@report["ready_for_complete"]} />
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp gate_metric(assigns) do
    ~H"""
    <div class="flex items-center justify-between px-2 py-1 rounded bg-base border border-border/50">
      <span class="text-[9px] text-muted">{@label}</span>
      <span class="text-[10px] font-mono font-bold text-default">{@value}</span>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :ready, :boolean, required: true

  defp gate_verdict(%{ready: true} = assigns) do
    ~H"""
    <div class="flex items-center gap-1.5 text-[10px]">
      <span class="w-1.5 h-1.5 rounded-full bg-success" />
      <span class="text-success font-semibold">{@label}</span>
    </div>
    """
  end

  defp gate_verdict(assigns) do
    ~H"""
    <div class="flex items-center gap-1.5 text-[10px]">
      <span class="w-1.5 h-1.5 rounded-full bg-error/50" />
      <span class="text-muted">{@label}</span>
    </div>
    """
  end
end
