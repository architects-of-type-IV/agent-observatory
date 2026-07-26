defmodule MemoriesClient.HTTP do
  @moduledoc """
  Behaviour for the HTTP transport.

  The client itself only builds requests and maps responses; how the bytes move
  is somebody else's problem. That keeps this project dependency-free — the
  default adapter is OTP's own `:httpc` — while letting an application that
  already uses Req, Finch, or Tesla plug that in instead and get its pooling,
  retries, and telemetry for free.

  Configure with:

      config :memories_client, http: MyApp.ReqAdapter

  ## Implementing one

  A Req adapter is about ten lines:

      defmodule MyApp.ReqAdapter do
        @behaviour MemoriesClient.HTTP

        @impl true
        def post(url, body, headers) do
          case Req.post(url, body: body, headers: headers) do
            {:ok, %{status: status, body: body}} -> {:ok, status, body}
            {:error, reason} -> {:error, reason}
          end
        end
      end

  The response body may be returned either as a raw string or as an
  already-decoded map — adapters that decode JSON themselves need no special
  handling.
  """

  @doc """
  POST `body` to `url` with `headers`.

  Return `{:ok, status, body}` for any completed request, including 4xx and 5xx
  — the client decides what counts as a failure. Reserve `{:error, reason}` for
  transport failures, where no response arrived at all.
  """
  @callback post(url :: String.t(), body :: String.t(), headers :: [{String.t(), String.t()}]) ::
              {:ok, status :: non_neg_integer(), body :: String.t() | map()} | {:error, term()}
end
