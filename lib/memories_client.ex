defmodule MemoriesClient do
  @moduledoc """
  Client for the Memories knowledge-graph API.

  Three operations: write observations into the graph (`ingest/2`), retrieve
  matching facts (`search/2`), and ask a natural-language question over it
  (`query_memory/2`).

  Extracted from the ICHOR IV agent observatory, where an app-manager agent used
  it to record what it saw and recall it during conversations. No dependencies —
  the HTTP transport is a behaviour, defaulting to OTP's `:httpc`.

  ## Wire format

  The API is AshJsonApi, so requests are `application/vnd.api+json` with a
  `{"data": {...}}` envelope. That is handled here; callers pass plain values.

  ## Responses

  Responses are normalised into flat maps with atom keys, so callers never touch
  raw JSON string keys. Any field the server omits comes back `nil` rather than
  missing, which means a caller can pattern-match without checking for key
  presence first.

  ## Setup

      config :memories_client,
        url: "https://memories.example.com",
        api_key: {:system, "MEMORIES_API_KEY"},
        group_id: "archon",
        user_id: "archon"

  ## Example

      {:ok, result} = MemoriesClient.ingest("The deploy pipeline uses Oban.", source: "agent")
      {:ok, facts}  = MemoriesClient.search("deploy pipeline", limit: 5)
      {:ok, answer} = MemoriesClient.query_memory("How do deploys work?")
  """

  require Logger

  alias MemoriesClient.Config

  @typedoc """
  A single ingest, or a chunked one when the content was split server-side.

  Check for the `:chunked` key to tell them apart.
  """
  @type ingest_result ::
          %{
            episode_id: String.t() | nil,
            group_id: String.t() | nil,
            status: String.t() | nil,
            sync_status: String.t() | nil
          }
          | %{
              chunked: true,
              chunk_count: non_neg_integer() | nil,
              episodes: [map()]
            }

  @typedoc "One edge or episode matching a search."
  @type search_result :: %{
          uuid: String.t() | nil,
          fact: String.t() | nil,
          name: String.t() | nil,
          source: String.t() | nil,
          target: String.t() | nil,
          score: float() | nil,
          created_at: String.t() | nil
        }

  @typedoc "An answer with its supporting citations and context."
  @type query_result :: %{
          answer: String.t() | nil,
          citations: [map()] | nil,
          context: map() | nil
        }

  @typedoc "`{:http_error, status, body}` for a server response, or a transport reason."
  @type error :: {:http_error, non_neg_integer(), term()} | term()

  @doc """
  Search the graph for edges or episodes matching `query`.

  ## Options

    * `:scope` — `"edges"` (default) or `"episodes"`
    * `:limit` — maximum results, default 10
    * `:user_id` — override the configured user id
  """
  @spec search(String.t(), keyword()) :: {:ok, [search_result()]} | {:error, error()}
  def search(query, opts \\ []) do
    body = %{
      query: query,
      user_id: Keyword.get_lazy(opts, :user_id, &Config.user_id/0),
      scope: to_string(Keyword.get(opts, :scope, "edges")),
      limit: Keyword.get(opts, :limit, 10)
    }

    with {:ok, results} <- post("/api/graph/search", body) do
      {:ok, results |> List.wrap() |> Enum.map(&to_search_result/1)}
    end
  end

  @doc """
  Ingest content into the graph.

  ## Options

    * `:type` — content type, default `"text"`
    * `:source` — what produced it, default `"agent"`
    * `:space` — optional namespace within the group
    * `:extraction_instructions` — optional guidance for entity extraction
    * `:user_id` — override the configured user id
  """
  @spec ingest(String.t(), keyword()) :: {:ok, ingest_result()} | {:error, error()}
  def ingest(content, opts \\ []) do
    body =
      %{
        content: content,
        user_id: Keyword.get_lazy(opts, :user_id, &Config.user_id/0),
        type: Keyword.get(opts, :type, "text"),
        source: Keyword.get(opts, :source, "agent")
      }
      |> put_optional(:space, Keyword.get(opts, :space))
      |> put_optional(:extraction_instructions, Keyword.get(opts, :extraction_instructions))

    with {:ok, response} <- post("/api/episodes/ingest", body) do
      {:ok, to_ingest_result(response)}
    end
  end

  @doc """
  Ask a natural-language question over the graph.

  ## Options

    * `:limit` — how many supporting items to consider, default 10
  """
  @spec query_memory(String.t(), keyword()) :: {:ok, query_result()} | {:error, error()}
  def query_memory(query, opts \\ []) do
    body = %{query: query, limit: Keyword.get(opts, :limit, 10)}

    with {:ok, response} <- post("/api/memories/query", body) do
      {:ok, to_query_result(response)}
    end
  end

  @doc "The configured group id."
  @spec group_id() :: String.t()
  defdelegate group_id, to: Config

  @doc "The configured user id."
  @spec user_id() :: String.t()
  defdelegate user_id, to: Config

  # Private

  defp post(path, body) do
    url = Config.url() <> path
    payload = JSON.encode!(%{data: body})

    case Config.http().post(url, payload, headers()) do
      {:ok, status, response} when status in 200..202 ->
        {:ok, decode(response)}

      {:ok, status, response} ->
        Logger.warning("MemoriesClient #{path} returned #{status}: #{inspect(response)}")
        {:error, {:http_error, status, decode(response)}}

      {:error, reason} ->
        Logger.warning("MemoriesClient #{path} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp headers do
    [
      {"authorization", "Bearer #{Config.api_key()}"},
      {"content-type", "application/vnd.api+json"},
      {"accept", "application/vnd.api+json"}
    ]
  end

  # Adapters may hand back a raw body or one they already decoded. Accept both,
  # and leave anything undecodable alone rather than failing the call.
  defp decode(body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, decoded} -> decoded
      {:error, _} -> body
    end
  end

  defp decode(body), do: body

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp to_ingest_result(%{"chunked" => true} = response) do
    %{
      chunked: true,
      chunk_count: response["chunk_count"],
      episodes: response["episodes"] |> List.wrap() |> Enum.map(&to_single_ingest/1)
    }
  end

  defp to_ingest_result(response), do: to_single_ingest(response)

  defp to_single_ingest(response) when is_map(response) do
    %{
      episode_id: response["episode_id"],
      group_id: response["group_id"],
      status: response["status"],
      sync_status: response["sync_status"]
    }
  end

  defp to_single_ingest(_), do: %{episode_id: nil, group_id: nil, status: nil, sync_status: nil}

  defp to_search_result(item) when is_map(item) do
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

  defp to_search_result(_),
    do: %{uuid: nil, fact: nil, name: nil, source: nil, target: nil, score: nil, created_at: nil}

  defp to_query_result(response) when is_map(response) do
    %{
      answer: response["answer"],
      citations: response["citations"],
      context: response["context"]
    }
  end

  defp to_query_result(_), do: %{answer: nil, citations: nil, context: nil}
end
