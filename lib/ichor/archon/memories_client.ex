defmodule Ichor.Archon.MemoriesClient do
  @moduledoc """
  HTTP client for the Memories knowledge graph API.

  Archon uses this to ingest observations and search its knowledge graph
  for recall during conversations. All operations are scoped to Archon's
  dedicated group_id namespace.
  """

  import Ichor.MapHelpers, only: [maybe_put: 3]

  require Logger

  defp memories_config, do: Application.fetch_env!(:ichor, :memories)
  defp memories_url, do: Keyword.fetch!(memories_config(), :url)
  defp api_key, do: Keyword.fetch!(memories_config(), :api_key)
  defp group_id_default, do: Keyword.fetch!(memories_config(), :group_id)
  defp user_id_default, do: Keyword.fetch!(memories_config(), :user_id)

  @spec search(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def search(query, opts \\ []) do
    scope = Keyword.get(opts, :scope, "edges")
    limit = Keyword.get(opts, :limit, 10)
    space = Keyword.get(opts, :space)

    body =
      %{
        query: query,
        group_id: group_id_default(),
        user_id: user_id_default(),
        scope: to_string(scope),
        limit: limit
      }
      |> maybe_put(:space, space)

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
        group_id: group_id_default(),
        user_id: user_id_default(),
        type: type,
        source: source
      }
      |> maybe_put(:space, space)

    post("/api/episodes/ingest", body)
  end

  @spec query_memory(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def query_memory(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    body = %{
      query: query,
      group_id: group_id_default(),
      limit: limit
    }

    post("/api/memories/query", body)
  end

  @spec group_id() :: String.t()
  def group_id, do: group_id_default()

  @spec user_id() :: String.t()
  def user_id, do: user_id_default()

  defp post(path, body) do
    url = memories_url() <> path

    case Req.post(url, json: body, headers: auth_headers()) do
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
