defmodule ObservatoryWeb.Components.PipelineComponents do
  @moduledoc """
  Pipeline view -- DAG visualization and task table for swarm pipelines.
  Shows tasks arranged by execution wave with dependency edges.
  """

  use Phoenix.Component
  import ObservatoryWeb.ObservatoryComponents

  embed_templates "pipeline_components/*"

  # ═══════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════

  defp dag_border("completed", true, _), do: "border-emerald-500/60 ring-1 ring-emerald-500/20"
  defp dag_border("completed", _, true), do: "border-indigo-500/60"
  defp dag_border("completed", _, _), do: "border-emerald-500/30"
  defp dag_border("in_progress", true, _), do: "border-blue-500/60 ring-1 ring-blue-500/20"
  defp dag_border("in_progress", _, true), do: "border-indigo-500/60"
  defp dag_border("in_progress", _, _), do: "border-blue-500/40"
  defp dag_border("failed", _, _), do: "border-red-500/40"
  defp dag_border(_, _, true), do: "border-indigo-500/60"
  defp dag_border(_, true, _), do: "border-zinc-600 ring-1 ring-zinc-500/20"
  defp dag_border(_, _, _), do: "border-zinc-800"

  defp dag_bg("completed"), do: "bg-emerald-500/5"
  defp dag_bg("in_progress"), do: "bg-blue-500/5"
  defp dag_bg("failed"), do: "bg-red-500/5"
  defp dag_bg(_), do: "bg-zinc-900/50"

  defp dag_dot("completed"), do: "bg-emerald-400"
  defp dag_dot("in_progress"), do: "bg-blue-400 animate-pulse"
  defp dag_dot("failed"), do: "bg-red-400"
  defp dag_dot("pending"), do: "bg-zinc-500"
  defp dag_dot(_), do: "bg-zinc-600"

  defp task_badge_class("completed"),
    do: "px-1.5 py-0.5 rounded text-[10px] bg-emerald-500/15 text-emerald-400"

  defp task_badge_class("in_progress"),
    do: "px-1.5 py-0.5 rounded text-[10px] bg-blue-500/15 text-blue-400"

  defp task_badge_class("failed"),
    do: "px-1.5 py-0.5 rounded text-[10px] bg-red-500/15 text-red-400"

  defp task_badge_class("pending"),
    do: "px-1.5 py-0.5 rounded text-[10px] bg-zinc-700 text-zinc-400"

  defp task_badge_class(_), do: "px-1.5 py-0.5 rounded text-[10px] bg-zinc-800 text-zinc-500"

  defp short_timestamp(""), do: ""
  defp short_timestamp(nil), do: ""

  defp short_timestamp(ts) when is_binary(ts) do
    case String.split(ts, "T") do
      [_, time_part] -> String.slice(time_part, 0, 8)
      _ -> ts
    end
  end
end
