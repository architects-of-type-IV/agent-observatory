defmodule ObservatoryWeb.Components.Feed.SessionGroup do
  @moduledoc """
  Agent block component -- one per session with full metadata,
  clear start/stop indicators, collapsible subagent blocks, and segments.
  """

  use Phoenix.Component
  import ObservatoryWeb.ObservatoryComponents
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.DashboardSessionHelpers
  import ObservatoryWeb.Components.Feed.ToolChain
  import ObservatoryWeb.Components.Feed.StandaloneEvent
  alias ObservatoryWeb.DashboardFeedHelpers

  embed_templates "session_group/*"

  # ═══════════════════════════════════════════════════════
  # Segment dispatch -- routes to embedded templates
  # ═══════════════════════════════════════════════════════

  defp segment(%{segment: %{type: :parent}} = assigns), do: parent_segment(assigns)
  defp segment(%{segment: %{type: :subagent}} = assigns), do: subagent_segment(assigns)

  # ═══════════════════════════════════════════════════════
  # Role badge (small, kept inline)
  # ═══════════════════════════════════════════════════════

  defp role_badge(%{role: :lead} = assigns) do
    ~H"""
    <span class="text-[10px] font-mono font-bold px-1.5 py-0.5 rounded bg-amber-500/15 text-amber-400 border border-amber-500/30">
      LEAD
    </span>
    """
  end

  defp role_badge(%{role: :worker} = assigns) do
    ~H"""
    <span class="text-[10px] font-mono px-1.5 py-0.5 rounded bg-cyan-500/15 text-cyan-400 border border-cyan-500/30">
      WORKER
    </span>
    """
  end

  defp role_badge(%{role: :relay} = assigns) do
    ~H"""
    <span class="text-[10px] font-mono px-1.5 py-0.5 rounded bg-violet-500/15 text-violet-400 border border-violet-500/30">
      RELAY
    </span>
    """
  end

  defp role_badge(assigns) do
    ~H"""
    <span class="text-[10px] font-mono px-1.5 py-0.5 rounded bg-zinc-700 text-zinc-500">
      SESSION
    </span>
    """
  end

  # ═══════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════

  defp agent_display_name(group) do
    cond do
      group.agent_name && group.agent_name != "" -> group.agent_name
      group.cwd -> Path.basename(group.cwd || "")
      true -> short_session(group.session_id)
    end
  end

  defp permission_label("acceptEdits"), do: "auto-edit"
  defp permission_label("bypassPermissions"), do: "bypass"
  defp permission_label("default"), do: "default"
  defp permission_label("plan"), do: "plan"
  defp permission_label(other) when is_binary(other), do: other
  defp permission_label(_), do: nil

  defp session_end_reason(group) do
    cond do
      group.session_end && is_map(group.session_end.payload) ->
        group.session_end.payload["reason"]

      true ->
        nil
    end
  end

  defp span_duration(%{start_time: st, end_time: et}) when not is_nil(st) and not is_nil(et) do
    DateTime.diff(et, st, :millisecond)
  end

  defp span_duration(_), do: nil

  defp depth_style(0), do: "border border-zinc-800 bg-zinc-900/40"
  defp depth_style(1), do: "border border-cyan-500/20 bg-zinc-900/30 ml-4"
  defp depth_style(_), do: "border border-violet-500/15 bg-zinc-900/20 ml-8"
end
