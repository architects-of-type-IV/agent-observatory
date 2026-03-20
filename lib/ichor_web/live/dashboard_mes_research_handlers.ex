defmodule IchorWeb.DashboardMesResearchHandlers do
  @moduledoc """
  Handle events for the MES Research Facility tab.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Ichor.Factory.ResearchStore

  @spec dispatch(String.t(), map(), Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def dispatch("mes_research_search", %{"query" => query}, socket) do
    results = do_search(query)

    socket
    |> assign(:mes_research_results, results)
    |> assign(:selected_research_item, nil)
  end

  def dispatch("mes_select_research_entity", %{"id" => id}, socket) do
    item = find_item(socket.assigns.mes_research_entities, id)
    assign(socket, :selected_research_item, item)
  end

  def dispatch("mes_select_research_episode", %{"id" => id}, socket) do
    item = find_item(socket.assigns.mes_research_episodes, id)
    assign(socket, :selected_research_item, item)
  end

  def dispatch("mes_research_refresh", _params, socket) do
    load_research_data(socket)
  end

  @spec load_research_data(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def load_research_data(socket) do
    entities = safe_fetch(&ResearchStore.list_entities/0)
    episodes = safe_fetch(&ResearchStore.recent_episodes/0)

    socket
    |> assign(:mes_research_entities, entities)
    |> assign(:mes_research_episodes, episodes)
  end

  defp do_search(""), do: []

  defp do_search(query) do
    case ResearchStore.search(query) do
      {:ok, results} -> results
      {:error, _} -> []
    end
  end

  defp safe_fetch(fun) do
    case fun.() do
      {:ok, data} when is_list(data) -> data
      _ -> []
    end
  rescue
    _ -> []
  end

  defp find_item(items, id) do
    Enum.find(items, fn
      %{"id" => item_id} -> item_id == id
      %{id: item_id} -> to_string(item_id) == id
      _ -> false
    end)
  end
end
