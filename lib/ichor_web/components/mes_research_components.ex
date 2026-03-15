defmodule IchorWeb.Components.MesResearchComponents do
  @moduledoc """
  Components for the MES Research Facility tab.
  Displays knowledge graph entities, facts, and research episodes
  from the Memories API.
  """

  use Phoenix.Component

  attr :entities, :list, required: true
  attr :episodes, :list, required: true
  attr :results, :list, required: true
  attr :selected, :any, default: nil

  def research_tab(assigns) do
    ~H"""
    <div class="flex flex-1 overflow-hidden">
      <%!-- Left: Search + Lists --%>
      <div class="flex-1 flex flex-col overflow-hidden">
        <%!-- Search bar --%>
        <div class="px-3 py-2 border-b border-border">
          <form phx-submit="mes_research_search" class="flex gap-2">
            <input
              type="text"
              name="query"
              placeholder="Search knowledge graph..."
              class="flex-1 px-2.5 py-1.5 text-[11px] rounded bg-surface border border-subtle text-default placeholder:text-muted focus:outline-none focus:border-brand"
              autocomplete="off"
            />
            <button
              type="submit"
              class="px-2.5 py-1.5 text-[10px] font-semibold rounded bg-brand/15 text-brand hover:bg-brand/25 transition-colors"
            >
              Search
            </button>
            <button
              type="button"
              phx-click="mes_research_refresh"
              class="px-2.5 py-1.5 text-[10px] font-semibold rounded bg-surface border border-subtle text-default hover:bg-raised transition-colors"
            >
              Refresh
            </button>
          </form>
        </div>

        <%!-- Search results --%>
        <div :if={@results != []} class="border-b border-border">
          <div class="px-3 py-1.5 bg-base/80">
            <span class="text-[9px] font-semibold text-low uppercase tracking-wider">
              Search Results ({length(@results)})
            </span>
          </div>
          <div class="max-h-40 overflow-auto">
            <div
              :for={result <- @results}
              class="px-3 py-2 border-b border-border/50 text-[11px]"
            >
              <span :if={result.fact} class="text-default">{result.fact}</span>
              <span :if={result.name} class="text-brand font-mono">{result.name}</span>
              <div :if={result.source || result.target} class="text-[10px] text-muted mt-0.5">
                <span :if={result.source}>{result.source}</span>
                <span :if={result.source && result.target}> &rarr; </span>
                <span :if={result.target}>{result.target}</span>
              </div>
            </div>
          </div>
        </div>

        <div class="flex-1 overflow-auto">
          <%!-- Empty state --%>
          <div
            :if={@entities == [] && @episodes == []}
            class="flex-1 flex items-center justify-center h-full"
          >
            <div class="ichor-empty">
              <p class="ichor-empty-title">No research data yet</p>
              <p class="ichor-empty-desc">
                Research will appear here as the factory produces subsystem briefs.
              </p>
            </div>
          </div>

          <%!-- Entities --%>
          <div :if={@entities != []}>
            <div class="px-3 py-1.5 bg-base/80 sticky top-0 z-10 border-b border-border">
              <span class="text-[9px] font-semibold text-low uppercase tracking-wider">
                Entities ({length(@entities)})
              </span>
            </div>
            <div
              :for={entity <- @entities}
              phx-click="mes_select_research_entity"
              phx-value-id={entity_id(entity)}
              class={[
                "px-3 py-2 border-b border-border/50 cursor-pointer transition-colors",
                if(selected?(entity, @selected),
                  do: "border-l-2 border-l-brand bg-brand/5 pl-2.5",
                  else: "hover:bg-brand/[0.03]"
                )
              ]}
            >
              <div class="flex items-center gap-2">
                <span class="text-[11px] font-semibold text-high">
                  {entity_name(entity)}
                </span>
                <span
                  :if={entity_type(entity)}
                  class="text-[9px] px-1.5 py-0.5 rounded bg-interactive/10 text-interactive"
                >
                  {entity_type(entity)}
                </span>
              </div>
              <p
                :if={entity_summary(entity)}
                class="text-[10px] text-muted mt-0.5 line-clamp-1"
              >
                {entity_summary(entity)}
              </p>
            </div>
          </div>

          <%!-- Episodes --%>
          <div :if={@episodes != []}>
            <div class="px-3 py-1.5 bg-base/80 sticky top-0 z-10 border-b border-border">
              <span class="text-[9px] font-semibold text-low uppercase tracking-wider">
                Research Documents ({length(@episodes)})
              </span>
            </div>
            <div
              :for={episode <- @episodes}
              phx-click="mes_select_research_episode"
              phx-value-id={episode_id(episode)}
              class={[
                "px-3 py-2 border-b border-border/50 cursor-pointer transition-colors",
                if(selected?(episode, @selected),
                  do: "border-l-2 border-l-brand bg-brand/5 pl-2.5",
                  else: "hover:bg-brand/[0.03]"
                )
              ]}
            >
              <div class="flex items-center gap-2">
                <span
                  :if={episode_source(episode)}
                  class="text-[9px] px-1.5 py-0.5 rounded bg-cyan/10 text-cyan font-mono"
                >
                  {episode_source(episode)}
                </span>
                <span
                  :if={episode_type(episode)}
                  class="text-[9px] text-muted"
                >
                  {episode_type(episode)}
                </span>
              </div>
              <p class="text-[10px] text-default mt-1 line-clamp-2">
                {episode_excerpt(episode)}
              </p>
            </div>
          </div>
        </div>
      </div>

      <%!-- Right: Detail panel --%>
      <div
        :if={@selected}
        class="w-[400px] shrink-0 border-l border-border bg-zinc-900/50 overflow-y-auto"
      >
        <.research_detail item={@selected} />
      </div>
    </div>
    """
  end

  defp research_detail(%{item: %{"name" => _}} = assigns) do
    ~H"""
    <div class="p-4">
      <h2 class="text-base font-bold text-high tracking-tight leading-tight mb-1">
        {entity_name(@item)}
      </h2>
      <span
        :if={entity_type(@item)}
        class="inline-block text-[9px] px-1.5 py-0.5 rounded bg-interactive/10 text-interactive mb-3"
      >
        {entity_type(@item)}
      </span>
      <p
        :if={entity_summary(@item)}
        class="text-[11px] text-default leading-relaxed mb-4"
      >
        {entity_summary(@item)}
      </p>

      <div :if={@item["aliases"] && @item["aliases"] != []} class="mb-3">
        <h4 class="text-[9px] font-semibold text-low uppercase tracking-wider mb-1.5">
          Aliases
        </h4>
        <div class="flex flex-wrap gap-1">
          <span
            :for={a <- @item["aliases"]}
            class="text-[9px] px-1.5 py-0.5 rounded bg-surface border border-subtle text-default"
          >
            {a}
          </span>
        </div>
      </div>

      <div :if={@item["attributes"] && @item["attributes"] != %{}} class="mb-3">
        <h4 class="text-[9px] font-semibold text-low uppercase tracking-wider mb-1.5">
          Attributes
        </h4>
        <div class="font-mono text-[10px] text-default p-2.5 rounded bg-surface border border-subtle whitespace-pre-wrap leading-relaxed">
          {inspect_attrs(@item["attributes"])}
        </div>
      </div>

      <div class="mt-4 pt-3 border-t border-border/50 text-[10px] text-muted">
        <span :if={@item["id"]}>ID: <span class="font-mono text-default">{@item["id"]}</span></span>
      </div>
    </div>
    """
  end

  defp research_detail(%{item: %{"content" => _}} = assigns) do
    ~H"""
    <div class="p-4">
      <div class="flex items-center gap-2 mb-3">
        <span
          :if={episode_source(@item)}
          class="text-[9px] px-1.5 py-0.5 rounded bg-cyan/10 text-cyan font-mono"
        >
          {episode_source(@item)}
        </span>
        <span
          :if={episode_type(@item)}
          class="text-[9px] px-1.5 py-0.5 rounded bg-surface border border-subtle text-default"
        >
          {episode_type(@item)}
        </span>
      </div>

      <div class="font-mono text-[10px] text-default p-3 rounded bg-surface border border-subtle whitespace-pre-wrap leading-relaxed max-h-[600px] overflow-auto">
        {@item["content"]}
      </div>

      <div class="mt-4 pt-3 border-t border-border/50 text-[10px] text-muted">
        <span :if={@item["id"]}>ID: <span class="font-mono text-default">{@item["id"]}</span></span>
      </div>
    </div>
    """
  end

  defp research_detail(assigns) do
    ~H"""
    <div class="p-4 text-[11px] text-muted">
      Select an entity or document to view details.
    </div>
    """
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp entity_id(%{"id" => id}), do: id
  defp entity_id(_), do: ""

  defp entity_name(%{"name" => name}), do: name
  defp entity_name(_), do: "Unknown"

  defp entity_type(%{"primary_type" => t}) when is_binary(t), do: t
  defp entity_type(_), do: nil

  defp entity_summary(%{"summary" => s}) when is_binary(s) and s != "", do: s
  defp entity_summary(_), do: nil

  defp episode_id(%{"id" => id}), do: id
  defp episode_id(_), do: ""

  defp episode_source(%{"source" => s}) when is_binary(s), do: s
  defp episode_source(_), do: nil

  defp episode_type(%{"type" => t}) when is_binary(t), do: t
  defp episode_type(_), do: nil

  defp episode_excerpt(%{"content" => c}) when is_binary(c), do: String.slice(c, 0, 200)
  defp episode_excerpt(_), do: ""

  defp selected?(%{"id" => id}, %{"id" => sel_id}), do: id == sel_id
  defp selected?(_, _), do: false

  defp inspect_attrs(attrs) when is_map(attrs) do
    attrs
    |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> Enum.join("\n")
  end

  defp inspect_attrs(_), do: ""
end
