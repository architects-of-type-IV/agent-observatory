defmodule Observatory.Archon.MemoriesClient do
  @moduledoc """
  HTTP client for the Memories knowledge graph API.

  Archon uses this to ingest observations and search its knowledge graph
  for recall during conversations. All operations are scoped to Archon's
  dedicated group_id namespace.
  """

  require Logger

  @memories_url "http://localhost:4000"
  @archon_group_id "0f8eae17-15fc-5af1-8761-0093dc9b5027"
  @archon_user_id "8fe50fd6-f0da-5adc-9251-6417dc3092e8"

  @spec search(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def search(query, opts \\ []) do
    scope = Keyword.get(opts, :scope, "edges")
    limit = Keyword.get(opts, :limit, 10)
    space = Keyword.get(opts, :space)

    body =
      %{
        query: query,
        group_id: @archon_group_id,
        user_id: @archon_user_id,
        scope: to_string(scope),
        limit: limit
      }
      |> maybe_put("space", space)

    post("/api/graph/search", body)
  end

  @spec ingest(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def ingest(content, opts \\ []) do
    type = Keyword.get(opts, :type, "text")
    source = Keyword.get(opts, :source, "agent")
    space = Keyword.get(opts, :space)

    body =
      %{
        content: content,
        group_id: @archon_group_id,
        user_id: @archon_user_id,
        type: type,
        source: source
      }
      |> maybe_put("space", space)

    post("/api/episodes/ingest", body)
  end

  @spec query_memory(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def query_memory(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    body = %{
      query: query,
      group_id: @archon_group_id,
      limit: limit
    }

    post("/api/memories/query", body)
  end

  @spec group_id() :: String.t()
  def group_id, do: @archon_group_id

  @spec user_id() :: String.t()
  def user_id, do: @archon_user_id

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp post(path, body) do
    url = @memories_url <> path

    case Req.post(url, json: body) do
      {:ok, %{status: status, body: body}} when status in [200, 202] ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("MemoriesClient #{path} returned #{status}: #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.warning("MemoriesClient #{path} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
