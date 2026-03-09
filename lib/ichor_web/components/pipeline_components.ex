defmodule IchorWeb.Components.PipelineComponents do
  @moduledoc """
  Pipeline view -- kanban board and task detail for swarm pipelines.
  Tasks grouped by status with click-to-select detail panel.
  """

  use Phoenix.Component
  import IchorWeb.IchorComponents

  embed_templates "pipeline_components/*"

  # DAG node styling helpers
  defp dag_border("completed", true, _), do: "border-success/60 ring-1 ring-success/20"
  defp dag_border("completed", _, true), do: "border-interactive/60"
  defp dag_border("completed", _, _), do: "border-success/30"
  defp dag_border("in_progress", true, _), do: "border-info/60 ring-1 ring-info/20"
  defp dag_border("in_progress", _, true), do: "border-interactive/60"
  defp dag_border("in_progress", _, _), do: "border-info/40"
  defp dag_border("failed", _, _), do: "border-error/40"
  defp dag_border(_, _, true), do: "border-interactive/60"
  defp dag_border(_, true, _), do: "border-border-subtle ring-1 ring-low/20"
  defp dag_border(_, _, _), do: "border-border"

  defp dag_bg("completed"), do: "bg-success/5"
  defp dag_bg("in_progress"), do: "bg-info/5"
  defp dag_bg("failed"), do: "bg-error/5"
  defp dag_bg(_), do: "bg-base/50"

  defp dag_dot("completed"), do: "bg-success"
  defp dag_dot("in_progress"), do: "bg-info animate-pulse"
  defp dag_dot("failed"), do: "bg-error"
  defp dag_dot("pending"), do: "bg-low"
  defp dag_dot(_), do: "bg-highlight"

  defp task_badge_class("completed"),
    do: "px-1.5 py-0.5 rounded text-[10px] bg-success/15 text-success"

  defp task_badge_class("in_progress"),
    do: "px-1.5 py-0.5 rounded text-[10px] bg-info/15 text-info"

  defp task_badge_class("failed"),
    do: "px-1.5 py-0.5 rounded text-[10px] bg-error/15 text-error"

  defp task_badge_class("pending"),
    do: "px-1.5 py-0.5 rounded text-[10px] bg-highlight text-default"

  defp task_badge_class("blocked"),
    do: "px-1.5 py-0.5 rounded text-[10px] bg-brand/15 text-brand"

  defp task_badge_class(_), do: "px-1.5 py-0.5 rounded text-[10px] bg-raised text-low"

  defp priority_color("critical"), do: "text-error"
  defp priority_color("high"), do: "text-brand"
  defp priority_color("medium"), do: "text-default"
  defp priority_color("low"), do: "text-muted"
  defp priority_color(_), do: "text-muted"

  defp short_timestamp(""), do: ""
  defp short_timestamp(nil), do: ""

  defp short_timestamp(ts) when is_binary(ts) do
    case String.split(ts, "T") do
      [_, time_part] -> String.slice(time_part, 0, 8)
      _ -> ts
    end
  end
end
