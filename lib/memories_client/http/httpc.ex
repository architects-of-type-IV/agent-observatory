defmodule MemoriesClient.HTTP.Httpc do
  @moduledoc """
  Default `MemoriesClient.HTTP` adapter, built on OTP's `:httpc`.

  Chosen because it ships with Erlang, so the client needs no dependencies. It
  is adequate for low-volume calls; for anything busy, point `:http` at an
  adapter over a pooled client instead.

  TLS verification is on, using the OS certificate store via
  `:public_key.cacerts_get/0`. Override the whole option list with
  `:httpc_ssl_options` if you need a custom CA bundle — but do not use that to
  turn verification off.

  Timeouts default to 30 s (request) and 15 s (connect), configurable as
  `:timeout_ms` and `:connect_timeout_ms`.
  """

  require Logger

  @behaviour MemoriesClient.HTTP

  @impl true
  def post(url, body, headers) do
    request = {
      String.to_charlist(url),
      Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end),
      content_type(headers),
      body
    }

    case :httpc.request(:post, request, http_options(), body_format: :binary) do
      {:ok, {{_version, status, _reason}, _headers, response_body}} ->
        {:ok, status, response_body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # :httpc takes the content type separately from the header list, and ignores a
  # "content-type" header if you leave it in there.
  defp content_type(headers) do
    headers
    |> Enum.find_value("application/json", fn {k, v} ->
      if String.downcase(k) == "content-type", do: v
    end)
    |> String.to_charlist()
  end

  defp http_options do
    [
      timeout: get(:timeout_ms, 30_000),
      connect_timeout: get(:connect_timeout_ms, 15_000),
      ssl: ssl_options()
    ]
  end

  defp ssl_options do
    Application.get_env(:memories_client, :httpc_ssl_options) ||
      [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        depth: 3,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
  end

  defp get(key, default), do: Application.get_env(:memories_client, key, default)
end
