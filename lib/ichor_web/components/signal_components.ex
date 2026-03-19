defmodule IchorWeb.Components.SignalComponents do
  @moduledoc """
  Components for the /signals nervous system page.
  The live feed uses a Phoenix stream of {seq, %Message{}} tuples.
  Per-signal rendering is delegated to IchorWeb.SignalFeed.Renderer.
  """
  use Phoenix.Component

  alias Ichor.Signals.{Catalog, Message}
  alias IchorWeb.SignalFeed.Renderer

  attr :streams, :any, required: true
  attr :stream_filter, :string, required: true
  attr :stream_paused, :boolean, required: true

  def signals_view(assigns) do
    catalog = Catalog.all() |> Enum.sort_by(fn {name, _} -> name end)
    categories = Catalog.categories()

    assigns =
      assigns
      |> assign(:catalog, catalog)
      |> assign(:categories, categories)

    ~H"""
    <div class="h-full flex overflow-hidden">
      <%!-- Left: Signal Catalog --%>
      <div class="w-80 border-r border-border overflow-y-auto shrink-0">
        <div class="px-3 py-2 border-b border-border sticky top-0 bg-base/95 backdrop-blur z-10">
          <h3 class="text-[10px] font-semibold text-low uppercase tracking-wider">Signal Catalog</h3>
          <span class="text-[9px] text-muted">
            {length(@catalog)} signals across {length(@categories)} categories
          </span>
        </div>

        <div :for={cat <- @categories} class="border-b border-border/50">
          <div class="px-3 py-1.5 bg-raised/30">
            <span class={"text-[9px] font-bold uppercase tracking-widest #{category_color(cat)}"}>
              {cat}
            </span>
          </div>
          <div
            :for={{name, info} <- Catalog.by_category(cat)}
            class="px-3 py-1.5 border-t border-border/20 hover:bg-raised/40 transition"
          >
            <div class="flex items-center gap-1.5">
              <span :if={info.dynamic} class="text-[8px] text-brand bg-brand/10 px-1 rounded">
                dyn
              </span>
              <button
                phx-click="stream_filter_topic"
                phx-value-topic={"#{cat}:#{name}"}
                class="font-mono text-[11px] text-interactive hover:underline cursor-pointer text-left truncate"
              >
                {name}
              </button>
            </div>
            <div class="mt-0.5 pl-2">
              <span class="text-[10px] text-muted">{info.doc}</span>
              <span :if={info.keys != []} class="text-[9px] font-mono text-default ml-1">
                ({Enum.join(info.keys, ", ")})
              </span>
            </div>
          </div>
        </div>
      </div>

      <%!-- Right: Live Feed --%>
      <div class="flex-1 flex flex-col overflow-hidden">
        <div class="px-3 py-1.5 border-b border-border flex items-center gap-2 shrink-0 bg-base/95 backdrop-blur">
          <h3 class="text-[10px] font-semibold text-low uppercase tracking-wider shrink-0">
            Live Feed
          </h3>
          <form phx-change="stream_search" class="flex-1">
            <input
              type="text"
              name="q"
              value={@stream_filter}
              placeholder="Filter by signal, category, or content..."
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
        </div>

        <div class="flex-1 overflow-y-auto" id="stream-feed" phx-hook="StreamAutoScroll">
          <table class="w-full text-[11px]">
            <thead class="sticky top-0 bg-base/95 backdrop-blur z-10">
              <tr class="text-left text-[9px] text-muted uppercase tracking-wider">
                <th class="px-2 py-1 w-[70px]">Time</th>
                <th class="px-2 py-1 w-[80px]">Category</th>
                <th class="px-2 py-1 w-[120px]">Signal</th>
                <th class="px-2 py-1">Detail</th>
              </tr>
            </thead>
            <tbody id="signals" phx-update="stream">
              <tr
                :for={{dom_id, {seq, message}} <- @streams.signals}
                :if={passes_filter?(message, @stream_filter)}
                id={dom_id}
                class={"border-b border-raised hover:bg-surface-raised/50 #{row_class(message)}"}
              >
                <td class="px-2 py-0.5 text-medium font-mono text-[10px] w-[70px]">
                  {format_ts(message.timestamp)}
                </td>
                <td class="px-2 py-0.5 w-[80px]">
                  <span class={"text-[10px] font-medium #{category_color(message.domain)}"}>
                    {message.domain}
                  </span>
                </td>
                <td class="px-2 py-0.5 w-[120px]">
                  <button
                    phx-click="stream_filter_topic"
                    phx-value-topic={"#{message.domain}:#{message.name}"}
                    class={"font-mono text-[10px] cursor-pointer hover:underline #{category_color(message.domain)}"}
                  >
                    {message.name}
                  </button>
                </td>
                <td class="px-2 py-0.5 flex items-center gap-1 flex-wrap">
                  <Renderer.render seq={seq} message={message} />
                </td>
              </tr>
            </tbody>
          </table>

          <div
            :if={@stream_paused}
            class="flex items-center justify-center h-16 text-muted text-[11px]"
          >
            Feed paused
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_ts(nil), do: "--:--:--"

  defp format_ts(ms) when is_integer(ms) do
    total_seconds = div(ms, 1000)
    h = div(total_seconds, 3600) |> rem(24)
    m = div(total_seconds, 60) |> rem(60)
    s = rem(total_seconds, 60)
    :io_lib.format("~2..0B:~2..0B:~2..0B", [h, m, s]) |> IO.iodata_to_binary()
  end

  defp passes_filter?(_message, ""), do: true

  defp passes_filter?(%Message{domain: domain, name: name}, filter) do
    f = String.downcase(filter)

    String.contains?(Atom.to_string(domain), f) or
      String.contains?(Atom.to_string(name), f) or
      String.contains?("#{domain}:#{name}", f)
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
  defp category_color(:genesis), do: "text-brand"
  defp category_color(:dag), do: "text-info"
  defp category_color(:mes), do: "text-default"
  defp category_color(_), do: "text-muted"

  defp row_class(%Message{name: :agent_crashed}), do: "bg-error/5"
  defp row_class(%Message{name: :schema_violation}), do: "bg-error/5"
  defp row_class(%Message{name: :dead_letter}), do: "bg-error/5"

  defp row_class(%Message{name: name})
       when name in [:nudge_warning, :nudge_sent, :nudge_escalated, :nudge_zombie],
       do: "bg-brand/5"

  defp row_class(%Message{name: name}) when name in [:gate_passed, :gate_failed], do: "bg-info/5"
  defp row_class(_), do: ""
end
