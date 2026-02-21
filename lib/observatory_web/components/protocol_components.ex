defmodule ObservatoryWeb.Components.ProtocolComponents do
  @moduledoc """
  Protocols view -- cross-protocol message tracing and channel statistics.
  Shows how messages flow through HTTP, PubSub, Mailbox, and CommandQueue.
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.ObservatoryComponents

  embed_templates "protocol_components/*"

  # ═══════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════

  defp short_id(nil), do: "?"
  defp short_id("unknown"), do: "?"
  defp short_id("system"), do: "system"
  defp short_id("broadcast"), do: "all"
  defp short_id(id) when byte_size(id) > 12, do: String.slice(id, 0, 8) <> "..."
  defp short_id(id), do: id

  defp trace_type_label(:send_message), do: "message"
  defp trace_type_label(:team_create), do: "team"
  defp trace_type_label(:agent_spawn), do: "spawn"
  defp trace_type_label(other), do: to_string(other)

  defp trace_type_color(:send_message), do: "bg-indigo-500/15 text-indigo-400"
  defp trace_type_color(:team_create), do: "bg-cyan-500/15 text-cyan-400"
  defp trace_type_color(:agent_spawn), do: "bg-amber-500/15 text-amber-400"
  defp trace_type_color(_), do: "bg-zinc-700 text-zinc-400"

  defp hop_status_color(:received), do: "bg-emerald-400"
  defp hop_status_color(:delivered), do: "bg-emerald-400"
  defp hop_status_color(:broadcast), do: "bg-cyan-400"
  defp hop_status_color(:pending), do: "bg-amber-400"
  defp hop_status_color(:read), do: "bg-emerald-400"
  defp hop_status_color(_), do: "bg-zinc-500"

  defp hop_status_text(:received), do: "text-emerald-500"
  defp hop_status_text(:delivered), do: "text-emerald-500"
  defp hop_status_text(:broadcast), do: "text-cyan-500"
  defp hop_status_text(:pending), do: "text-amber-500"
  defp hop_status_text(:read), do: "text-emerald-500"
  defp hop_status_text(_), do: "text-zinc-600"

  defp format_seconds(0), do: "-"
  defp format_seconds(s) when s < 60, do: "#{s}s"
  defp format_seconds(s) when s < 3600, do: "#{div(s, 60)}m"
  defp format_seconds(s), do: "#{div(s, 3600)}h"
end
