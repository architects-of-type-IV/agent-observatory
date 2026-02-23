defmodule ObservatoryWeb.Components.PipelineComponents do
  @moduledoc """
  Pipeline view -- kanban board and task detail for swarm pipelines.
  Tasks grouped by status with click-to-select detail panel.
  """

  use Phoenix.Component
  import ObservatoryWeb.ObservatoryComponents

  embed_templates "pipeline_components/*"

  defp task_badge_class("completed"),
    do: "px-1.5 py-0.5 rounded text-[10px] bg-emerald-500/15 text-emerald-400"

  defp task_badge_class("in_progress"),
    do: "px-1.5 py-0.5 rounded text-[10px] bg-blue-500/15 text-blue-400"

  defp task_badge_class("failed"),
    do: "px-1.5 py-0.5 rounded text-[10px] bg-red-500/15 text-red-400"

  defp task_badge_class("pending"),
    do: "px-1.5 py-0.5 rounded text-[10px] bg-zinc-700 text-zinc-400"

  defp task_badge_class("blocked"),
    do: "px-1.5 py-0.5 rounded text-[10px] bg-amber-500/15 text-amber-400"

  defp task_badge_class(_), do: "px-1.5 py-0.5 rounded text-[10px] bg-zinc-800 text-zinc-500"

  defp priority_color("critical"), do: "text-red-400"
  defp priority_color("high"), do: "text-amber-400"
  defp priority_color("medium"), do: "text-zinc-400"
  defp priority_color("low"), do: "text-zinc-600"
  defp priority_color(_), do: "text-zinc-600"

  defp short_timestamp(""), do: ""
  defp short_timestamp(nil), do: ""

  defp short_timestamp(ts) when is_binary(ts) do
    case String.split(ts, "T") do
      [_, time_part] -> String.slice(time_part, 0, 8)
      _ -> ts
    end
  end
end
