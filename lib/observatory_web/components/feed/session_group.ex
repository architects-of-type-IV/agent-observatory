defmodule ObservatoryWeb.Components.Feed.SessionGroup do
  @moduledoc """
  Agent block component -- one per session with full metadata,
  clear start/stop indicators, collapsible subagent blocks, and segments.
  """

  use Phoenix.Component
  import ObservatoryWeb.ObservatoryComponents
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.DashboardSessionHelpers
  import ObservatoryWeb.Components.Feed.ToolExecutionBlock
  import ObservatoryWeb.Components.Feed.StandaloneEvent
  alias ObservatoryWeb.DashboardFeedHelpers

  attr :group, :map, required: true
  attr :selected_event, :map, default: nil
  attr :event_notes, :map, required: true
  attr :collapsed_sessions, :any, default: MapSet.new()
  attr :now, :any, required: true
  attr :depth, :integer, default: 0

  def session_group(assigns) do
    collapsed = MapSet.member?(assigns.collapsed_sessions, assigns.group.session_id)
    assigns = assign(assigns, :collapsed, collapsed)

    ~H"""
    <div class={[
      "rounded-lg overflow-hidden",
      depth_style(@depth),
      if(@group.is_active, do: "ring-1 ring-emerald-500/20", else: "")
    ]}>
      <%!-- Session Header (always visible, clickable to toggle) --%>
      <div
        class={[
          "px-3 py-2.5 flex flex-wrap items-center gap-x-3 gap-y-1 cursor-pointer select-none",
          if(@group.is_active, do: "bg-zinc-800/80 hover:bg-zinc-800", else: "bg-zinc-900/60 hover:bg-zinc-900/80")
        ]}
        phx-click="toggle_session_collapse"
        phx-value-session_id={@group.session_id}
      >
        <%!-- Collapse indicator --%>
        <span class="text-zinc-600 text-xs font-mono w-3 shrink-0">
          {if @collapsed, do: "+", else: "-"}
        </span>

        <%!-- Status dot + Agent name --%>
        <div class="flex items-center gap-2">
          <span class={[
            "w-2.5 h-2.5 rounded-full shrink-0",
            if(@group.is_active, do: "bg-emerald-400 animate-pulse", else: "bg-zinc-600")
          ]} />

          <span class="text-sm font-semibold text-zinc-200">
            {agent_display_name(@group)}
          </span>

          <.role_badge role={@group.role} />
        </div>

        <%!-- Session ID --%>
        <span class="text-xs font-mono text-zinc-600" title={@group.session_id}>
          {short_session(@group.session_id)}
        </span>

        <%!-- Model --%>
        <.model_badge :if={@group.model} model={@group.model} />

        <%!-- Permission mode --%>
        <span
          :if={@group.permission_mode}
          class="text-[10px] font-mono px-1.5 py-0.5 rounded bg-zinc-800 text-zinc-500 border border-zinc-700"
        >
          {permission_label(@group.permission_mode)}
        </span>

        <%!-- Source app --%>
        <span :if={@group.source_app} class="text-[10px] font-mono text-zinc-600">
          {String.upcase(@group.source_app || "")}
        </span>

        <span class="flex-1" />

        <%!-- Stats --%>
        <span class="text-xs font-mono text-zinc-500">
          {@group.event_count} events
        </span>
        <span :if={@group.tool_count > 0} class="text-xs font-mono text-zinc-600">
          {@group.tool_count} tools
        </span>
        <span :if={@group.subagent_count > 0} class="text-xs font-mono text-cyan-500">
          {@group.subagent_count} sub
        </span>

        <%!-- Time range --%>
        <span :if={@group.start_time} class="text-xs font-mono text-zinc-600">
          {format_time(@group.start_time)}
          {if @group.end_time && @group.end_time != @group.start_time, do: "- #{format_time(@group.end_time)}", else: ""}
        </span>

        <%!-- CWD --%>
        <span :if={@group.cwd} class="text-[10px] font-mono text-zinc-700 truncate max-w-[200px]" title={@group.cwd}>
          {abbreviate_cwd(@group.cwd)}
        </span>
      </div>

      <%!-- Collapsible body --%>
      <div :if={!@collapsed}>
        <%!-- Session Start Banner --%>
        <div
          :if={@group.session_start}
          class="px-3 py-1.5 bg-emerald-500/8 border-b border-emerald-500/20 flex items-center gap-3"
        >
          <span class="text-[10px] font-mono font-bold tracking-wider text-emerald-400 uppercase">
            Start
          </span>
          <span class="text-xs font-mono text-zinc-400">
            {format_time(@group.session_start.inserted_at)}
          </span>
          <span :if={@group.model} class="text-xs text-zinc-500">
            {@group.model}
          </span>
          <span :if={@group.cwd} class="text-xs font-mono text-zinc-600 truncate" title={@group.cwd}>
            {abbreviate_cwd(@group.cwd)}
          </span>
        </div>

        <%!-- Render segments --%>
        <div class="space-y-0">
          <.segment
            :for={segment <- @group.segments}
            segment={segment}
            selected_event={@selected_event}
            event_notes={@event_notes}
            collapsed_sessions={@collapsed_sessions}
            now={@now}
          />
        </div>

        <%!-- Session End / Stop Banner --%>
        <div
          :if={@group.session_end || @group.stop_event}
          class="px-3 py-1.5 bg-red-500/8 border-t border-red-500/20 flex items-center gap-3"
        >
          <span class="text-[10px] font-mono font-bold tracking-wider text-red-400 uppercase">
            {if @group.session_end, do: "End", else: "Stop"}
          </span>
          <span class="text-xs font-mono text-zinc-400">
            {format_time((@group.session_end || @group.stop_event).inserted_at)}
          </span>
          <span :if={@group.total_duration_ms} class="text-xs text-zinc-500">
            Duration: {format_duration(@group.total_duration_ms)}
          </span>
          <span :if={session_end_reason(@group)} class="text-xs text-zinc-600">
            {session_end_reason(@group)}
          </span>
        </div>

        <%!-- Active indicator --%>
        <div
          :if={@group.is_active && @group.end_time}
          class="px-3 py-1 bg-emerald-500/5 border-t border-emerald-500/10 flex items-center gap-2"
        >
          <span class="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" />
          <span class="text-[10px] font-mono text-emerald-500">
            Active -- last event {relative_time(@group.end_time, @now)}
          </span>
        </div>
      </div>
    </div>
    """
  end

  # ═══════════════════════════════════════════════════════
  # Segment rendering -- parent events vs subagent blocks
  # ═══════════════════════════════════════════════════════

  attr :segment, :map, required: true
  attr :selected_event, :map, default: nil
  attr :event_notes, :map, required: true
  attr :collapsed_sessions, :any, default: MapSet.new()
  attr :now, :any, required: true

  defp segment(%{segment: %{type: :parent}} = assigns) do
    ~H"""
    <div class="px-3 py-2 space-y-1">
      <% paired_ids = DashboardFeedHelpers.get_paired_tool_use_ids(@segment.tool_pairs) %>

      <.tool_execution_block
        :for={pair <- @segment.tool_pairs}
        pair={pair}
        selected_event={@selected_event}
        event_notes={@event_notes}
        now={@now}
      />

      <% standalone = DashboardFeedHelpers.get_standalone_events(@segment.events, paired_ids) %>
      <.standalone_event
        :for={event <- standalone}
        event={event}
        selected_event={@selected_event}
        event_notes={@event_notes}
        now={@now}
      />
    </div>
    """
  end

  defp segment(%{segment: %{type: :subagent}} = assigns) do
    agent_key = "sub:#{assigns.segment.agent_id}"
    collapsed = MapSet.member?(assigns.collapsed_sessions, agent_key)
    assigns = assign(assigns, :collapsed_sub, collapsed)
    assigns = assign(assigns, :agent_key, agent_key)

    ~H"""
    <div class="mx-2 my-1 rounded border border-cyan-500/20 bg-zinc-900/30 overflow-hidden">
      <%!-- Subagent header --%>
      <div
        class="px-3 py-1.5 flex items-center gap-2 cursor-pointer select-none hover:bg-zinc-800/50"
        phx-click="toggle_session_collapse"
        phx-value-session_id={@agent_key}
      >
        <span class="text-zinc-600 text-xs font-mono w-3 shrink-0">
          {if @collapsed_sub, do: "+", else: "-"}
        </span>

        <span class="w-2 h-2 rounded-full bg-cyan-400 shrink-0" />

        <span class="text-xs font-semibold text-cyan-300">
          {@segment.agent_type || "subagent"}
        </span>

        <span class="text-[10px] font-mono text-zinc-600">
          {short_session(@segment.agent_id || "")}
        </span>

        <span class="flex-1" />

        <span class="text-[10px] font-mono text-zinc-500">
          {@segment.event_count} events
        </span>
        <span :if={@segment.tool_count > 0} class="text-[10px] font-mono text-zinc-600">
          {@segment.tool_count} tools
        </span>

        <span :if={@segment.start_time} class="text-[10px] font-mono text-zinc-600">
          {format_time(@segment.start_time)}
          {if @segment.end_time, do: "- #{format_time(@segment.end_time)}", else: "..."}
        </span>

        <span :if={span_duration(@segment)} class="text-[10px] font-mono text-zinc-500">
          {format_duration(span_duration(@segment))}
        </span>
      </div>

      <%!-- Subagent body --%>
      <div :if={!@collapsed_sub}>
        <%!-- Start marker --%>
        <div class="px-3 py-1 bg-cyan-500/8 border-y border-cyan-500/15 flex items-center gap-2">
          <span class="text-[10px] font-mono font-bold tracking-wider text-cyan-400 uppercase">
            Spawn
          </span>
          <span class="text-[10px] font-mono text-zinc-500">
            {format_time(@segment.start_time)}
          </span>
          <span :if={@segment.agent_type} class="text-[10px] text-zinc-600">
            {@segment.agent_type}
          </span>
        </div>

        <%!-- Tool pairs and standalone events --%>
        <div class="px-3 py-1.5 space-y-1">
          <% paired_ids = DashboardFeedHelpers.get_paired_tool_use_ids(@segment.tool_pairs) %>

          <.tool_execution_block
            :for={pair <- @segment.tool_pairs}
            pair={pair}
            selected_event={@selected_event}
            event_notes={@event_notes}
            now={@now}
          />

          <% standalone = DashboardFeedHelpers.get_standalone_events(@segment.events, paired_ids) %>
          <.standalone_event
            :for={event <- standalone}
            event={event}
            selected_event={@selected_event}
            event_notes={@event_notes}
            now={@now}
          />
        </div>

        <%!-- Stop marker --%>
        <div
          :if={@segment.stop_event}
          class="px-3 py-1 bg-cyan-600/8 border-t border-cyan-600/15 flex items-center gap-2"
        >
          <span class="text-[10px] font-mono font-bold tracking-wider text-cyan-600 uppercase">
            Reap
          </span>
          <span class="text-[10px] font-mono text-zinc-500">
            {format_time(@segment.end_time)}
          </span>
          <span :if={span_duration(@segment)} class="text-[10px] text-zinc-500">
            {format_duration(span_duration(@segment))}
          </span>
        </div>
      </div>
    </div>
    """
  end

  # ═══════════════════════════════════════════════════════
  # Role badge
  # ═══════════════════════════════════════════════════════

  attr :role, :atom, required: true

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
