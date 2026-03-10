defmodule IchorWeb.Components.StreamComponents do
  @moduledoc """
  Components for the /stream PubSub monitor page.
  """
  use Phoenix.Component

  alias Ichor.Stream.TopicCatalog

  attr :stream_events, :list, required: true
  attr :stream_filter, :string, required: true
  attr :stream_paused, :boolean, required: true

  def stream_view(assigns) do
    catalog = TopicCatalog.all()
    categories = TopicCatalog.categories()

    filtered_events =
      if assigns.stream_filter == "" do
        assigns.stream_events
      else
        f = String.downcase(assigns.stream_filter)
        Enum.filter(assigns.stream_events, fn e ->
          String.contains?(String.downcase(e.topic), f) or
            String.contains?(String.downcase(e.summary), f) or
            String.contains?(String.downcase(e.shape), f)
        end)
      end

    assigns =
      assigns
      |> assign(:catalog, catalog)
      |> assign(:categories, categories)
      |> assign(:filtered_events, filtered_events)

    ~H"""
    <div class="h-full flex overflow-hidden">
      <%!-- Left: Topic Catalog (320px) --%>
      <div class="w-80 border-r border-border overflow-y-auto shrink-0">
        <div class="px-3 py-2 border-b border-border sticky top-0 bg-base/95 backdrop-blur z-10">
          <h3 class="text-[10px] font-semibold text-low uppercase tracking-wider">PubSub Topics</h3>
          <span class="text-[9px] text-muted">{length(@catalog)} topics across {length(@categories)} categories</span>
        </div>

        <div :for={cat <- @categories} class="border-b border-border/50">
          <div class="px-3 py-1.5 bg-raised/30">
            <span class={"text-[9px] font-bold uppercase tracking-widest #{category_color(cat)}"}>{cat}</span>
          </div>
          <div :for={entry <- TopicCatalog.by_category(cat)} class="px-3 py-1.5 border-t border-border/20 hover:bg-raised/40 transition">
            <div class="flex items-center gap-1.5">
              <span :if={entry[:dynamic]} class="text-[8px] text-brand bg-brand/10 px-1 rounded">dyn</span>
              <span :if={entry[:subscribers] == []} class="text-[8px] text-error/60 bg-error/5 px-1 rounded">no sub</span>
              <button
                phx-click="stream_filter_topic"
                phx-value-topic={entry.topic}
                class="font-mono text-[11px] text-interactive hover:underline cursor-pointer text-left truncate"
              >
                {entry.topic}
              </button>
            </div>
            <div :for={msg <- entry.messages} class="mt-0.5 pl-2">
              <span class="text-[10px] font-mono text-default">{msg.shape}</span>
              <span class="text-[9px] text-muted ml-1">{msg.description}</span>
            </div>
            <div class="mt-0.5 pl-2 flex flex-wrap gap-1">
              <span :for={b <- entry.broadcasters} class="text-[8px] text-success/80 bg-success/5 px-1 rounded">{b}</span>
              <span :for={s <- entry[:subscribers] || []} class="text-[8px] text-info/80 bg-info/5 px-1 rounded">{s}</span>
            </div>
          </div>
        </div>
      </div>

      <%!-- Right: Live Feed --%>
      <div class="flex-1 flex flex-col overflow-hidden">
        <%!-- Feed header --%>
        <div class="px-3 py-1.5 border-b border-border flex items-center gap-2 shrink-0 bg-base/95 backdrop-blur">
          <h3 class="text-[10px] font-semibold text-low uppercase tracking-wider shrink-0">Live Feed</h3>
          <form phx-change="stream_search" class="flex-1">
            <input
              type="text"
              name="q"
              value={@stream_filter}
              placeholder="Filter by topic, shape, or content..."
              autocomplete="off"
              phx-debounce="100"
              class="w-full bg-raised/80 px-2 py-1 text-[11px] text-high placeholder-muted focus:outline-none border border-border-subtle/60 rounded"
            />
          </form>
          <button
            phx-click="stream_toggle_pause"
            class={"text-[10px] px-2 py-1 rounded transition cursor-pointer #{if @stream_paused, do: "bg-brand/20 text-brand", else: "bg-raised text-default hover:bg-highlight"}"}
          >
            {if @stream_paused, do: "Paused", else: "Pause"}
          </button>
          <button
            phx-click="stream_clear"
            class="text-[10px] px-2 py-1 rounded bg-raised text-default hover:bg-highlight transition cursor-pointer"
          >
            Clear
          </button>
          <span class="text-[9px] text-muted">{length(@filtered_events)} events</span>
        </div>

        <%!-- Event list --%>
        <div class="flex-1 overflow-y-auto" id="stream-feed" phx-hook="StreamAutoScroll">
          <table class="w-full text-[11px]">
            <thead class="sticky top-0 bg-base/95 backdrop-blur z-10">
              <tr class="text-left text-[9px] text-muted uppercase tracking-wider">
                <th class="px-2 py-1 w-16">Time</th>
                <th class="px-2 py-1 w-40">Topic</th>
                <th class="px-2 py-1 w-36">Shape</th>
                <th class="px-2 py-1">Summary</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={event <- @filtered_events}
                class={"border-t border-border/20 hover:bg-raised/40 transition #{topic_row_class(event.topic)}"}
              >
                <td class="px-2 py-0.5 font-mono text-muted whitespace-nowrap">{format_time(event.at)}</td>
                <td class="px-2 py-0.5">
                  <button
                    phx-click="stream_filter_topic"
                    phx-value-topic={event.topic}
                    class={"font-mono cursor-pointer hover:underline #{topic_text_color(event.topic)}"}
                  >
                    {event.topic}
                  </button>
                </td>
                <td class="px-2 py-0.5 font-mono text-default">{event.shape}</td>
                <td class="px-2 py-0.5 text-high truncate max-w-[400px]">{event.summary}</td>
              </tr>
            </tbody>
          </table>

          <div :if={@filtered_events == []} class="flex items-center justify-center h-32 text-muted text-[11px]">
            {if @stream_paused, do: "Feed paused", else: "Waiting for events..."}
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp format_time(dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp category_color(:events), do: "text-success"
  defp category_color(:fleet), do: "text-brand"
  defp category_color(:gateway), do: "text-cyan"
  defp category_color(:agent), do: "text-interactive"
  defp category_color(:hitl), do: "text-error"
  defp category_color(:mesh), do: "text-brand"
  defp category_color(:team), do: "text-info"
  defp category_color(:monitoring), do: "text-default"
  defp category_color(:messages), do: "text-success"
  defp category_color(:memory), do: "text-interactive"
  defp category_color(:system), do: "text-muted"
  defp category_color(_), do: "text-muted"

  defp topic_text_color("events:" <> _), do: "text-success"
  defp topic_text_color("fleet:" <> _), do: "text-brand"
  defp topic_text_color("gateway:" <> _), do: "text-cyan"
  defp topic_text_color("agent:" <> _), do: "text-interactive"
  defp topic_text_color("session:" <> _), do: "text-error"
  defp topic_text_color("team" <> _), do: "text-info"
  defp topic_text_color("protocols:" <> _), do: "text-default"
  defp topic_text_color("quality:" <> _), do: "text-default"
  defp topic_text_color("pane:" <> _), do: "text-default"
  defp topic_text_color("swarm:" <> _), do: "text-default"
  defp topic_text_color("messages:" <> _), do: "text-success"
  defp topic_text_color("memory:" <> _), do: "text-interactive"
  defp topic_text_color("heartbeat"), do: "text-muted"
  defp topic_text_color(_), do: "text-muted"

  defp topic_row_class("agent:crashes"), do: "bg-error/5"
  defp topic_row_class("agent:nudge"), do: "bg-brand/5"
  defp topic_row_class("quality:gate"), do: "bg-info/5"
  defp topic_row_class("gateway:violations"), do: "bg-error/5"
  defp topic_row_class("gateway:dlq"), do: "bg-error/5"
  defp topic_row_class(_), do: ""
end
