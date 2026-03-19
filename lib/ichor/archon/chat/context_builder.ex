defmodule Ichor.Archon.Chat.ContextBuilder do
  @moduledoc """
  Builds auto-retrieved memory context messages for Archon chat turns.
  """

  alias Ichor.Archon.MemoriesClient
  alias LangChain.Message

  @timeout_ms 2_000

  @doc "Retrieve memory context from the knowledge graph and return system messages."
  @spec build_messages(String.t()) :: {:ok, list()}
  def build_messages(user_input) do
    client = client_module()

    tasks = [
      Task.async(fn -> client.search(user_input, scope: "edges", limit: 5) end),
      Task.async(fn -> client.search(user_input, scope: "episodes", limit: 3) end)
    ]

    [edges_result, episodes_result] =
      tasks
      |> Task.yield_many(@timeout_ms)
      |> Enum.map(fn {task, result} ->
        case result do
          {:ok, value} ->
            value

          _ ->
            Task.shutdown(task, :brutal_kill)
            {:error, :timeout}
        end
      end)

    context = String.trim("#{format_edges(edges_result)}\n#{format_episodes(episodes_result)}")

    if context == "" do
      {:ok, []}
    else
      {:ok,
       [
         Message.new_system!("""
         [MEMORY CONTEXT - auto-retrieved from your knowledge graph]
         This is your conversation history with the Architect and accumulated knowledge. Use it to answer questions about what you discussed, what you know, and what happened previously. Do NOT call recent_messages for this -- that tool is only for inter-agent pipeline messages.
         #{context}\
         """)
       ]}
    end
  rescue
    _ -> {:ok, []}
  end

  @doc "Format edge search results into a facts text block."
  @spec format_edges(term()) :: String.t()
  def format_edges({:ok, edges}) when is_list(edges) and edges != [] do
    items =
      edges
      |> Enum.take(10)
      |> Enum.map_join("\n", fn edge ->
        "- #{edge.fact || edge.name || inspect(edge)}"
      end)

    "Facts:\n#{items}"
  end

  def format_edges({:ok, %{"results" => %{"edges" => edges}}})
      when is_list(edges) and edges != [] do
    items =
      edges
      |> Enum.take(10)
      |> Enum.map_join("\n", fn edge ->
        "- #{edge["fact"] || edge["name"] || inspect(edge)}"
      end)

    "Facts:\n#{items}"
  end

  def format_edges(_), do: ""

  @doc "Format episode search results into a recent conversations text block."
  @spec format_episodes(term()) :: String.t()
  def format_episodes({:ok, episodes}) when is_list(episodes) and episodes != [] do
    items =
      episodes
      |> Enum.take(5)
      |> Enum.map_join("\n", fn episode ->
        content = Map.get(episode, :content) || Map.get(episode, "content") || ""
        "- #{String.slice(content, 0, 200)}"
      end)

    "Recent conversations:\n#{items}"
  end

  def format_episodes({:ok, %{"results" => %{"episodes" => episodes}}})
      when is_list(episodes) and episodes != [] do
    items =
      episodes
      |> Enum.take(5)
      |> Enum.map_join("\n", fn episode ->
        "- #{String.slice(episode["content"] || "", 0, 200)}"
      end)

    "Recent conversations:\n#{items}"
  end

  def format_episodes(_), do: ""

  defp client_module do
    Application.get_env(:ichor, :archon_memories_client_module, MemoriesClient)
  end
end
