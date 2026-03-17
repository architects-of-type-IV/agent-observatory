defmodule IchorWeb.Components.MesArtifactComponents do
  @moduledoc """
  Public API for MES artifact rendering.
  Provides the artifact list (tab browsing) and reader sidebar (detail view).
  """

  use Phoenix.Component

  alias IchorWeb.Components.MesReaderComponents

  defdelegate reader_sidebar(assigns), to: MesReaderComponents

  # ── Artifact List ────────────────────────────────────────────────────

  attr :genesis_node, :any, required: true
  attr :sub_tab, :atom, required: true
  attr :selected, :any, default: nil

  def artifact_list(assigns) do
    items = build_items(assigns.genesis_node, assigns.sub_tab)
    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="w-full overflow-y-auto">
      <div :if={@items == []} class="px-4 py-10 text-center text-[11px] text-muted">
        No artifacts yet.
      </div>
      <button
        :for={item <- @items}
        phx-click="genesis_select_artifact"
        phx-value-type={item.type}
        phx-value-id={item.id}
        class={[
          "flex items-center gap-2.5 px-3.5 py-2.5 border-b border-subtle w-full text-left text-default transition-colors",
          "hover:bg-white/[0.03]",
          if(selected?(@selected, item.type, item.id), do: "bg-brand/10", else: "bg-transparent")
        ]}
      >
        <span
          :if={item.code != ""}
          class={["font-mono text-[9px] flex-shrink-0 min-w-[50px]", item.code_class]}
        >
          {item.code}
        </span>
        <span class="text-[11px] font-semibold flex-1 truncate">{item.label}</span>
        <span
          :if={item.badge != ""}
          class="text-[8px] px-1.5 py-0.5 rounded font-bold uppercase flex-shrink-0 bg-brand/10 text-brand"
        >
          {item.badge}
        </span>
      </button>
    </div>
    """
  end

  defp selected?({type, id}, type, id), do: true
  defp selected?(_, _, _), do: false

  defp build_items(node, :decisions) do
    node
    |> safe_list(:adrs)
    |> Enum.map(fn adr ->
      %{
        type: :adr,
        id: adr.id,
        code: adr.code,
        code_class: "text-brand",
        label: adr.title,
        badge: to_string(adr.status)
      }
    end)
  end

  defp build_items(node, :requirements) do
    features =
      node
      |> safe_list(:features)
      |> Enum.map(fn f ->
        %{
          type: :feature,
          id: f.id,
          code: f.code,
          code_class: "text-interactive",
          label: f.title,
          badge: ""
        }
      end)

    use_cases =
      node
      |> safe_list(:use_cases)
      |> Enum.map(fn uc ->
        %{
          type: :use_case,
          id: uc.id,
          code: uc.code,
          code_class: "text-interactive",
          label: uc.title,
          badge: ""
        }
      end)

    features ++ use_cases
  end

  defp build_items(node, :checkpoints) do
    checkpoints =
      node
      |> safe_list(:checkpoints)
      |> Enum.map(fn cp ->
        %{
          type: :checkpoint,
          id: cp.id,
          code: "",
          code_class: "",
          label: cp.title,
          badge: to_string(cp.mode)
        }
      end)

    conversations =
      node
      |> safe_list(:conversations)
      |> Enum.map(fn conv ->
        %{
          type: :conversation,
          id: conv.id,
          code: "",
          code_class: "",
          label: conv.title,
          badge: to_string(conv.mode)
        }
      end)

    checkpoints ++ conversations
  end

  defp build_items(node, :roadmap) do
    node
    |> safe_list(:phases)
    |> Enum.map(fn phase ->
      %{
        type: :phase,
        id: phase.id,
        code: "P#{phase.number}",
        code_class: "text-success",
        label: phase.title,
        badge: ""
      }
    end)
  end

  defp build_items(_node, _tab), do: []

  defp safe_list(nil, _key), do: []

  defp safe_list(node, key) do
    case Map.get(node, key, []) do
      list when is_list(list) -> list
      _ -> []
    end
  end
end
