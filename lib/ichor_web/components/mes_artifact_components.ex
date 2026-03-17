defmodule IchorWeb.Components.MesArtifactComponents do
  @moduledoc """
  Reader sidebar for viewing artifact content with cross-references and markdown rendering.
  """

  use Phoenix.Component

  # ── Reader Sidebar ───────────────────────────────────────────────────
  # Close button emits "genesis_close_reader" -- wiring agent must add the handler clause
  # to set genesis_selected to nil.

  attr :genesis_node, :any, required: true
  attr :selected, :any, required: true
  attr :sub_tab, :atom, required: true

  def reader_sidebar(assigns) do
    item = find_selected(assigns.genesis_node, assigns.selected)
    assigns = assign(assigns, item: item)

    ~H"""
    <div :if={@item} class="flex-1 overflow-y-auto bg-base">
      <div class="px-6 py-5 max-w-2xl">
        <div class="flex items-start justify-between mb-1">
          <div class="flex items-center gap-2">
            <span :if={@item.code != ""} class="font-mono text-[13px] font-bold text-brand">
              {@item.code}
            </span>
            <span
              :if={@item.badge != ""}
              class="text-[9px] px-2 py-0.5 rounded font-bold uppercase tracking-wider bg-brand/10 text-brand"
            >
              {@item.badge}
            </span>
          </div>
          <button
            phx-click="genesis_close_reader"
            class="px-2 py-1 text-[9px] font-semibold bg-surface border border-subtle text-muted rounded hover:text-default transition-colors"
          >
            Close
          </button>
        </div>

        <h2 class="text-[17px] font-bold text-high leading-snug mt-1.5">{@item.title}</h2>

        <div :if={@item.refs != []} class="flex flex-wrap gap-1.5 mt-2.5">
          <span
            :for={ref <- @item.refs}
            phx-click="genesis_select_artifact"
            phx-value-type={ref.type}
            phx-value-id={ref.id}
            class="text-[9px] px-2 py-0.5 rounded bg-brand/10 text-brand font-mono cursor-pointer font-semibold hover:bg-brand/20"
          >
            {ref.label}
          </span>
        </div>

        <div class="genesis-prose mt-5">
          {Phoenix.HTML.raw(render_markdown(@item.content))}
        </div>
      </div>
    </div>
    <div :if={is_nil(@item)} class="flex-1 flex items-center justify-center text-muted text-[12px]">
      Select an artifact to view its content.
    </div>
    """
  end

  # ── Markdown Rendering ───────────────────────────────────────────────

  defp render_markdown(nil), do: ""
  defp render_markdown(""), do: ""

  defp render_markdown(content) do
    case Earmark.as_html(content, compact_output: true) do
      {:ok, html, _} -> html
      {:error, html, _} -> html
    end
  end

  # ── Item Lookup ──────────────────────────────────────────────────────

  defp find_selected(_node, nil), do: nil
  defp find_selected(nil, _selected), do: nil

  defp find_selected(node, {:adr, id}) do
    node
    |> safe_list(:adrs)
    |> Enum.find(&(&1.id == id))
    |> build_adr_item()
  end

  defp find_selected(node, {:feature, id}) do
    node
    |> safe_list(:features)
    |> Enum.find(&(&1.id == id))
    |> build_feature_item()
  end

  defp find_selected(node, {:use_case, id}) do
    node
    |> safe_list(:use_cases)
    |> Enum.find(&(&1.id == id))
    |> build_use_case_item()
  end

  defp find_selected(node, {:checkpoint, id}) do
    node
    |> safe_list(:checkpoints)
    |> Enum.find(&(&1.id == id))
    |> build_checkpoint_item()
  end

  defp find_selected(node, {:conversation, id}) do
    node
    |> safe_list(:conversations)
    |> Enum.find(&(&1.id == id))
    |> build_conversation_item()
  end

  defp find_selected(node, {:phase, id}) do
    node
    |> safe_list(:phases)
    |> Enum.find(&(&1.id == id))
    |> build_phase_item()
  end

  defp find_selected(_node, _selected), do: nil

  # ── Item Builders ────────────────────────────────────────────────────

  defp build_adr_item(nil), do: nil

  defp build_adr_item(adr) do
    refs =
      adr
      |> Map.get(:related_adr_codes, [])
      |> safe_codes()
      |> Enum.map(&%{type: :adr, id: &1, label: &1})

    %{
      code: adr.code,
      title: adr.title,
      badge: to_string(adr.status),
      content: Map.get(adr, :content, ""),
      refs: refs
    }
  end

  defp build_feature_item(nil), do: nil

  defp build_feature_item(feature) do
    refs =
      feature
      |> Map.get(:adr_codes, [])
      |> safe_codes()
      |> Enum.map(&%{type: :adr, id: &1, label: &1})

    %{
      code: feature.code,
      title: feature.title,
      badge: "",
      content: Map.get(feature, :content, ""),
      refs: refs
    }
  end

  defp build_use_case_item(nil), do: nil

  defp build_use_case_item(use_case) do
    refs =
      case Map.get(use_case, :feature_code) do
        nil -> []
        code -> [%{type: :feature, id: code, label: code}]
      end

    %{
      code: use_case.code,
      title: use_case.title,
      badge: "",
      content: Map.get(use_case, :content, ""),
      refs: refs
    }
  end

  defp build_checkpoint_item(nil), do: nil

  defp build_checkpoint_item(checkpoint) do
    %{
      code: "",
      title: checkpoint.title,
      badge: to_string(checkpoint.mode),
      content: Map.get(checkpoint, :content, ""),
      refs: []
    }
  end

  defp build_conversation_item(nil), do: nil

  defp build_conversation_item(conversation) do
    %{
      code: "",
      title: conversation.title,
      badge: to_string(conversation.mode),
      content: Map.get(conversation, :content, ""),
      refs: []
    }
  end

  defp build_phase_item(nil), do: nil

  defp build_phase_item(phase) do
    governed_by = Map.get(phase, :governed_by, "")

    refs =
      governed_by
      |> parse_governed_by()
      |> Enum.map(&%{type: :adr, id: &1, label: &1})

    %{
      code: "P#{phase.number}",
      title: phase.title,
      badge: "",
      content: Map.get(phase, :content, ""),
      refs: refs
    }
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp safe_list(node, key) do
    case Map.get(node, key, []) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp safe_codes(nil), do: []
  defp safe_codes(codes) when is_list(codes), do: codes
  defp safe_codes(_), do: []

  defp parse_governed_by(nil), do: []
  defp parse_governed_by(""), do: []

  defp parse_governed_by(str) when is_binary(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
