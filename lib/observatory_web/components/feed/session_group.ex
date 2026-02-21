defmodule ObservatoryWeb.Components.Feed.SessionGroup do
  @moduledoc """
  Agent block component -- one per session with full metadata,
  clear start/stop indicators, collapsible turns, and activity phases.

  ## Composable primitives

  All tree rows use two structural components:

  - `feed_nest/1` -- indentation wrapper (border-l + padding)
  - `feed_row/1`  -- row line with gutter (+/- or ·), click behavior, selection highlight

  These are the ONLY places that define row sizing, nesting depth, and click handlers.
  Templates provide content via inner_block.
  """

  use Phoenix.Component
  import ObservatoryWeb.ObservatoryComponents
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.DashboardSessionHelpers
  alias ObservatoryWeb.DashboardFeedHelpers

  embed_templates "session_group/*"

  # ═══════════════════════════════════════════════════════
  # Composable primitives
  # ═══════════════════════════════════════════════════════

  @doc """
  Nesting wrapper. Provides the tree indentation line.
  All nested content in the feed goes through this.
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def feed_nest(assigns) do
    ~H"""
    <div class={["ml-4 border-l-2 border-zinc-800 pl-3 py-0.5", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Row line with gutter indicator and click behavior.

  Mode is determined by which attrs are set:
  - `collapse_key` set -> collapsible row: +/- gutter, toggle_session_collapse click
  - `event_id` set     -> leaf row: · gutter, select_event click, selection highlight
  - neither            -> static row: · gutter, no click

  Content is provided via inner_block (everything after the gutter).
  """
  attr :collapse_key, :string, default: nil
  attr :expanded_sessions, :any, default: nil
  attr :event_id, :any, default: nil
  attr :selected_event, :map, default: nil
  slot :inner_block, required: true

  def feed_row(assigns) do
    expanded =
      if assigns.collapse_key && assigns.expanded_sessions do
        MapSet.member?(assigns.expanded_sessions, assigns.collapse_key)
      end

    selected =
      if assigns.event_id && assigns.selected_event do
        to_string(assigns.selected_event.id) == to_string(assigns.event_id)
      end

    clickable = assigns.collapse_key != nil || assigns.event_id != nil

    assigns =
      assigns
      |> assign(:expanded, expanded)
      |> assign(:selected, selected)
      |> assign(:clickable, clickable)

    ~H"""
    <div
      class={[
        "flex items-center gap-2 rounded px-1 -mx-1 py-0.5",
        if(@clickable, do: "cursor-pointer select-none hover:bg-zinc-800/30", else: ""),
        if(@selected, do: "bg-zinc-800/80 ring-1 ring-indigo-500/40", else: "")
      ]}
      phx-click={
        cond do
          @collapse_key -> "toggle_session_collapse"
          @event_id -> "select_event"
          true -> nil
        end
      }
      phx-value-session_id={@collapse_key}
      phx-value-id={if(@event_id && !@collapse_key, do: @event_id)}
    >
      <span class="text-zinc-600 text-[10px] font-mono w-3 shrink-0">
        <%= cond do %>
          <% @collapse_key && @expanded -> %>-
          <% @collapse_key -> %>+
          <% true -> %>&middot;
        <% end %>
      </span>
      {render_slot(@inner_block)}
    </div>
    """
  end

  # ═══════════════════════════════════════════════════════
  # Style helpers -- single source of truth for row element sizing
  # ═══════════════════════════════════════════════════════

  @doc "CSS class for a row label (PROMPT, RESEARCH, START, etc.)"
  def label_class(color), do: "text-xs font-mono font-bold uppercase tracking-wider #{color} shrink-0"

  @doc "CSS class for the main summary text (truncated, fills remaining space)"
  def summary_class(color \\ "text-zinc-500"), do: "text-xs #{color} truncate flex-1 min-w-0"

  @doc "CSS class for metadata stats (tool count, duration, time, etc.)"
  def stat_class(color \\ "text-zinc-600"), do: "text-xs font-mono #{color} shrink-0"

  # ═══════════════════════════════════════════════════════
  # Turn dispatch -- routes to embedded templates
  # ═══════════════════════════════════════════════════════

  defp render_item(%{item: %{type: :turn}} = assigns), do: conversation_turn(assigns)
  defp render_item(%{item: %{type: :preamble}} = assigns), do: preamble_segment(assigns)
  defp render_item(%{item: %{type: :subagent_stop}} = assigns), do: orphan_subagent(assigns)

  # ═══════════════════════════════════════════════════════
  # Tool pair -- start + done rows in one nest
  # ═══════════════════════════════════════════════════════

  attr :pair, :map, required: true
  attr :selected_event, :map, default: nil
  attr :event_notes, :map, required: true
  attr :expanded_sessions, :any, default: MapSet.new()
  attr :now, :any, required: true

  defp tool_pair(assigns) do
    ~H"""
    <.feed_nest class="space-y-0">
      <%!-- START --%>
      <.feed_row event_id={@pair.pre.id} selected_event={@selected_event}>
        <span class={label_class("text-amber-400")}>Start</span>
        <span class={label_class("text-indigo-400")}>{@pair.tool_name}</span>
        <span class={summary_class()}>{event_summary(@pair.pre)}</span>
        <span :if={(@pair[:permission_events] || []) != []} class={stat_class("text-amber-500/70")}>
          {length(@pair[:permission_events] || [])} perm
        </span>
        <span class={stat_class()}>{format_time(@pair.pre.inserted_at)}</span>
      </.feed_row>

      <%!-- DONE / FAIL --%>
      <.feed_row :if={@pair.post} event_id={@pair.post.id} selected_event={@selected_event}>
        <span class={label_class(if @pair.status == :failure, do: "text-red-400", else: "text-emerald-400")}>
          {if @pair.status == :failure, do: "Fail", else: "Done"}
        </span>
        <span class={label_class("text-indigo-400")}>{@pair.tool_name}</span>
        <span class={summary_class()}>{event_summary(@pair.post)}</span>
        <span :if={@pair.status == :success} class={stat_class(duration_color(@pair.duration_ms))}>
          {format_duration(@pair.duration_ms)}
        </span>
        <span class={stat_class()}>{format_time(@pair.post.inserted_at)}</span>
      </.feed_row>

      <%!-- RUNNING (no post yet) --%>
      <.feed_row :if={!@pair.post}>
        <span class={label_class("text-amber-400") <> " animate-pulse"}>Running</span>
        <span class={label_class("text-indigo-400")}>{@pair.tool_name}</span>
        <span class={stat_class("text-amber-400")}>
          {format_duration(DashboardFeedHelpers.elapsed_time_ms(@pair.pre, @now))}...
        </span>
      </.feed_row>
    </.feed_nest>
    """
  end

  # ═══════════════════════════════════════════════════════
  # Orphan subagent stop
  # ═══════════════════════════════════════════════════════

  defp orphan_subagent(assigns) do
    ~H"""
    <.feed_nest>
      <.feed_row event_id={@item.event.id} selected_event={@selected_event}>
        <span class={label_class("text-cyan-400")}>Subagent</span>
        <span class={summary_class()}>
          completed{if @item[:agent_id], do: " (#{short_session(@item[:agent_id])})", else: ""}
        </span>
        <span class={stat_class()}>{format_time(@item.event.inserted_at)}</span>
      </.feed_row>
    </.feed_nest>
    """
  end

  # ═══════════════════════════════════════════════════════
  # Preamble segment (events before first turn)
  # ═══════════════════════════════════════════════════════

  defp preamble_segment(assigns) do
    assigns = assign(assigns, :preamble_key, "preamble:#{(assigns.item.events |> List.first()).id}")

    ~H"""
    <% expanded = MapSet.member?(@expanded_sessions, @preamble_key) %>
    <.feed_nest>
      <.feed_row collapse_key={@preamble_key} expanded_sessions={@expanded_sessions}>
        <span class={label_class("text-zinc-500")}>Preamble</span>
        <span :if={@item.tool_count > 0} class={stat_class()}>{@item.tool_count} tools</span>
        <span :if={@item.total_duration_ms} class={stat_class(duration_color(@item.total_duration_ms))}>
          {format_duration(@item.total_duration_ms)}
        </span>
        <span :if={@item.start_time} class={stat_class()}>{format_time(@item.start_time)}</span>
      </.feed_row>

      <div :if={expanded && @item.phases != []} class="space-y-0">
        <.activity_phase
          :for={phase <- @item.phases}
          phase={phase}
          turn_id={"preamble"}
          selected_event={@selected_event}
          event_notes={@event_notes}
          expanded_sessions={@expanded_sessions}
          now={@now}
        />
      </div>
    </.feed_nest>
    """
  end

  # ═══════════════════════════════════════════════════════
  # Phase helpers
  # ═══════════════════════════════════════════════════════

  def phase_label(:research), do: "Research"
  def phase_label(:build), do: "Build"
  def phase_label(:verify), do: "Verify"
  def phase_label(:delegate), do: "Delegate"
  def phase_label(:communicate), do: "Communicate"
  def phase_label(:think), do: "Think"
  def phase_label(:other), do: "Other"

  def phase_color(:research), do: "text-blue-400"
  def phase_color(:build), do: "text-emerald-400"
  def phase_color(:verify), do: "text-amber-400"
  def phase_color(:delegate), do: "text-indigo-400"
  def phase_color(:communicate), do: "text-fuchsia-400"
  def phase_color(:think), do: "text-violet-400"
  def phase_color(:other), do: "text-zinc-400"

  # ═══════════════════════════════════════════════════════
  # Role badge
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

  defp depth_style(0), do: "border border-zinc-800 bg-zinc-900/40"
  defp depth_style(1), do: "border border-cyan-500/20 bg-zinc-900/30 ml-4"
  defp depth_style(_), do: "border border-violet-500/15 bg-zinc-900/20 ml-8"
end
