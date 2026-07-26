defmodule MemoriesClient.Config do
  @moduledoc """
  Runtime configuration for `MemoriesClient`.

      config :memories_client,
        url: "https://memories.example.com",
        api_key: {:system, "MEMORIES_API_KEY"},
        group_id: "archon",
        user_id: "archon",
        http: MemoriesClient.HTTP.Httpc

  `:url` and `:api_key` are required and raise if missing, naming the key — a
  clear error at the first call beats a 401 from the server. `:group_id` and
  `:user_id` are required only by the calls that send them.

  ## Secrets

  `:api_key` accepts `{:system, "VAR"}` to read an environment variable at call
  time, which keeps the secret out of compiled config. A plain string works too.
  """

  @doc "Base URL of the Memories API, with any trailing slash removed."
  @spec url() :: String.t()
  def url, do: :url |> fetch!() |> String.trim_trailing("/")

  @doc "API key, resolving `{:system, \"VAR\"}` against the environment."
  @spec api_key() :: String.t()
  def api_key do
    case fetch!(:api_key) do
      {:system, var} -> System.get_env(var) || raise_missing_env(var)
      key when is_binary(key) -> key
    end
  end

  @doc "Default group id namespace for this instance."
  @spec group_id() :: String.t()
  def group_id, do: fetch!(:group_id)

  @doc "Default user id sent with search and ingest calls."
  @spec user_id() :: String.t()
  def user_id, do: fetch!(:user_id)

  @doc "The configured `MemoriesClient.HTTP` adapter."
  @spec http() :: module()
  def http, do: Application.get_env(:memories_client, :http, MemoriesClient.HTTP.Httpc)

  defp fetch!(key) do
    case Application.fetch_env(:memories_client, key) do
      {:ok, value} ->
        value

      :error ->
        raise ArgumentError, """
        MemoriesClient is missing required configuration `#{inspect(key)}`. Set it with:

            config :memories_client, #{key}: ...
        """
    end
  end

  defp raise_missing_env(var) do
    raise ArgumentError,
          "MemoriesClient api_key is configured as {:system, #{inspect(var)}} " <>
            "but that environment variable is not set."
  end
end
