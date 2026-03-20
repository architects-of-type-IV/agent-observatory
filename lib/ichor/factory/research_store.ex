defmodule Ichor.Factory.ResearchStore do
  @moduledoc """
  Read-only interface to the Memories knowledge graph for MES research.
  Wraps GET endpoints for entities, facts, and episodes scoped to the
  research space. Uses the same config as `Ichor.Archon.MemoriesClient`.
  """

  require Logger

  alias Ichor.Archon.MemoriesClient

  @research_space "project:ichor:research"

  @spec search(String.t(), keyword()) :: {:ok, list()} | {:error, term()}
  def search(query, opts \\ []) do
    MemoriesClient.search(query, Keyword.put_new(opts, :limit, 20))
  end

  @spec list_entities(keyword()) :: {:ok, list()} | {:error, term()}
  def list_entities(opts \\ []) do
    limit = Keyword.get(opts, :limit, 30)
    get("/api/entities", %{space: @research_space, page: %{limit: limit}})
  end

  @spec list_facts(keyword()) :: {:ok, list()} | {:error, term()}
  def list_facts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    get("/api/facts", %{space: @research_space, page: %{limit: limit}})
  end

  @spec recent_episodes(non_neg_integer()) :: {:ok, list()} | {:error, term()}
  def recent_episodes(limit \\ 50) do
    get("/api/episodes", %{space: @research_space, page: %{limit: limit}})
  end

  @spec query(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def query(question, opts \\ []) do
    MemoriesClient.query_memory(question, opts)
  end

  defp get(path, params) do
    url = memories_url() <> path

    case Req.get(url, headers: headers(), params: flatten_params(params)) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, extract_data(body)}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[ResearchStore] GET #{path} returned #{status}: #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.warning("[ResearchStore] GET #{path} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_data(%{"data" => data}), do: data
  defp extract_data(data) when is_list(data), do: data
  defp extract_data(data), do: data

  defp flatten_params(params) do
    Enum.flat_map(params, fn
      {k, v} when is_map(v) ->
        Enum.map(v, fn {sk, sv} -> {"#{k}[#{sk}]", sv} end)

      {k, v} ->
        [{to_string(k), v}]
    end)
  end

  defp memories_config, do: Application.fetch_env!(:ichor, :memories)
  defp memories_url, do: Keyword.fetch!(memories_config(), :url)
  defp api_key, do: Keyword.fetch!(memories_config(), :api_key)

  defp headers do
    [
      {"authorization", "Bearer #{api_key()}"},
      {"accept", "application/vnd.api+json"}
    ]
  end
end
