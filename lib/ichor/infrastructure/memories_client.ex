defmodule Ichor.Infrastructure.MemoriesClient do
  @moduledoc """
  HTTP client for the Memories knowledge graph API.

  Archon uses this to ingest observations and search its knowledge graph
  for recall during conversations. All operations are scoped to Archon's
  dedicated group_id namespace.

  The Memories API uses AshJsonApi, so all requests use `application/vnd.api+json`
  with a `{"data": {args}}` envelope.

  ## Return shapes

  - `ingest/2` returns `{:ok, ingest_result()}` where the map has either a `:chunked` key
    (chunked ingest) or `:episode_id` (single ingest).
  - `search/2` returns `{:ok, [search_result()]}`.
  - `query_memory/2` returns `{:ok, query_result()}`.
  """

  require Logger

  @type ingest_result ::
          %{
            episode_id: String.t(),
            group_id: String.t(),
            status: String.t(),
            sync_status: String.t()
          }
          | %{
              chunked: true,
              chunk_count: non_neg_integer(),
              episodes: [
                %{
                  episode_id: String.t(),
                  group_id: String.t(),
                  status: String.t(),
                  sync_status: String.t()
                }
              ]
            }

  @type search_result :: %{
          uuid: String.t() | nil,
          fact: String.t() | nil,
          name: String.t() | nil,
          source: String.t() | nil,
          target: String.t() | nil,
          score: float() | nil,
          created_at: String.t() | nil
        }

  @type query_result :: %{
          answer: String.t() | nil,
          citations: [map()] | nil,
          context: map() | nil
        }

  defp memories_config, do: Application.fetch_env!(:ichor, :memories)
  defp memories_url, do: Keyword.fetch!(memories_config(), :url)
  defp api_key, do: Keyword.fetch!(memories_config(), :api_key)
  defp group_id_default, do: Keyword.fetch!(memories_config(), :group_id)
  defp user_id_default, do: Keyword.fetch!(memories_config(), :user_id)

  @doc "Search the Memories knowledge graph for edges or episodes matching the query."
  @spec search(String.t(), keyword()) :: {:ok, [search_result()]} | {:error, term()}
  def search(query, opts \\ []) do
    scope = Keyword.get(opts, :scope, "edges")
    limit = Keyword.get(opts, :limit, 10)

    body = %{
      query: query,
      user_id: user_id_default(),
      scope: to_string(scope),
      limit: limit
    }

    with {:ok, results} when is_list(results) <- post("/api/graph/search", body) do
      {:ok, Enum.map(results, &to_search_result/1)}
    end
  end

  @doc "Ingest content into the Memories knowledge graph."
  @spec ingest(String.t(), keyword()) :: {:ok, ingest_result()} | {:error, term()}
  def ingest(content, opts \\ []) do
    type = Keyword.get(opts, :type, "text")
    source = Keyword.get(opts, :source, "agent")
    space = Keyword.get(opts, :space)

    extraction_instructions = Keyword.get(opts, :extraction_instructions)

    body =
      %{
        content: content,
        user_id: user_id_default(),
        type: type,
        source: source
      }
      |> then(fn map -> if space, do: Map.put(map, :space, space), else: map end)
      |> then(fn map ->
        if extraction_instructions,
          do: Map.put(map, :extraction_instructions, extraction_instructions),
          else: map
      end)

    with {:ok, resp} <- post("/api/episodes/ingest", body) do
      {:ok, to_ingest_result(resp)}
    end
  end

  @doc "Query the Memories knowledge graph with a natural language question."
  @spec query_memory(String.t(), keyword()) :: {:ok, query_result()} | {:error, term()}
  def query_memory(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    body = %{
      query: query,
      limit: limit
    }

    with {:ok, resp} <- post("/api/memories/query", body) do
      {:ok, to_query_result(resp)}
    end
  end

  @doc "Return the configured group_id for this Archon instance."
  @spec group_id() :: String.t()
  def group_id, do: group_id_default()

  @doc "Return the configured user_id for this Archon instance."
  @spec user_id() :: String.t()
  def user_id, do: user_id_default()

  defp post(path, body) do
    url = memories_url() <> path
    encoded = JSON.encode!(%{data: body})

    case Req.post(url, body: encoded, headers: headers()) do
      {:ok, %{status: status, body: resp}} when status in 200..202 ->
        {:ok, resp}

      {:ok, %{status: status, body: resp}} ->
        Logger.warning("MemoriesClient #{path} returned #{status}: #{inspect(resp)}")
        {:error, {:http_error, status, resp}}

      {:error, reason} ->
        Logger.warning("MemoriesClient #{path} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp headers do
    [
      {"authorization", "Bearer #{api_key()}"},
      {"content-type", "application/vnd.api+json"},
      {"accept", "application/vnd.api+json"}
    ]
  end

  defp to_ingest_result(%{"chunked" => true} = resp) do
    %{
      chunked: true,
      chunk_count: resp["chunk_count"],
      episodes: Enum.map(resp["episodes"], &to_single_ingest/1)
    }
  end

  defp to_ingest_result(resp), do: to_single_ingest(resp)

  defp to_single_ingest(resp) do
    %{
      episode_id: resp["episode_id"],
      group_id: resp["group_id"],
      status: resp["status"],
      sync_status: resp["sync_status"]
    }
  end

  defp to_search_result(item) do
    %{
      uuid: item["uuid"],
      fact: item["fact"],
      name: item["name"],
      source: item["source"],
      target: item["target"],
      score: item["score"],
      created_at: item["created_at"]
    }
  end

  defp to_query_result(resp) do
    %{
      answer: resp["answer"],
      citations: resp["citations"],
      context: resp["context"]
    }
  end
end
